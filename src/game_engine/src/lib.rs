use candid::{CandidType, Deserialize, Nat, Principal};
use ic_cdk::{caller, query, update};
use ic_cdk_timers::{clear_timer, set_timer};
use ic_stable_structures::memory_manager::{MemoryId, MemoryManager, VirtualMemory};
use ic_stable_structures::{DefaultMemoryImpl, StableBTreeMap};
use serde::Serialize;
use std::cell::RefCell;
use std::time::Duration;

type Memory = VirtualMemory<DefaultMemoryImpl>;

#[derive(CandidType, Deserialize, Clone, Serialize)]
pub struct Player {
    pub id: Principal,
    pub username: String,
    pub level: u32,
    pub experience: u64,
    pub wins: u32,
    pub losses: u32,
    pub deck: Vec<Nat>, // NFT token IDs
    pub active_deck: Vec<Nat>, // Currently selected deck (max 5 cards)
}

#[derive(CandidType, Deserialize, Clone, Serialize)]
pub struct GameMatch {
    pub id: Nat,
    pub player1: Principal,
    pub player2: Principal,
    pub player1_deck: Vec<Nat>,
    pub player2_deck: Vec<Nat>,
    pub status: MatchStatus,
    pub current_turn: Principal,
    pub turn_number: u32,
    pub winner: Option<Principal>,
    pub start_time: u64,
    pub last_move_time: u64,
    pub moves: Vec<GameMove>,
}

#[derive(CandidType, Deserialize, Clone, Serialize)]
pub enum MatchStatus {
    WaitingForPlayer,
    Active,
    Finished,
    Cancelled,
}

#[derive(CandidType, Deserialize, Clone, Serialize)]
pub struct GameMove {
    pub player: Principal,
    pub move_type: MoveType,
    pub card_id: Option<Nat>,
    pub target_card_id: Option<Nat>,
    pub timestamp: u64,
}

#[derive(CandidType, Deserialize, Clone, Serialize)]
pub enum MoveType {
    PlayCard,
    Attack,
    UseSpecialAbility,
    EndTurn,
}

#[derive(CandidType, Deserialize)]
pub struct CreateMatchArgs {
    pub deck: Vec<Nat>,
}

#[derive(CandidType, Deserialize)]
pub struct JoinMatchArgs {
    pub match_id: Nat,
    pub deck: Vec<Nat>,
}

#[derive(CandidType, Deserialize)]
pub struct MakeMoveArgs {
    pub match_id: Nat,
    pub move_type: MoveType,
    pub card_id: Option<Nat>,
    pub target_card_id: Option<Nat>,
}

thread_local! {
    static MEMORY_MANAGER: RefCell<MemoryManager<DefaultMemoryImpl>> =
        RefCell::new(MemoryManager::init(DefaultMemoryImpl::default()));

    static PLAYERS: RefCell<StableBTreeMap<Principal, Player, Memory>> = RefCell::new(
        StableBTreeMap::init(
            MEMORY_MANAGER.with(|m| m.borrow().get(MemoryId::new(0))),
        )
    );

    static MATCHES: RefCell<StableBTreeMap<Nat, GameMatch, Memory>> = RefCell::new(
        StableBTreeMap::init(
            MEMORY_MANAGER.with(|m| m.borrow().get(MemoryId::new(1))),
        )
    );

    static NEXT_MATCH_ID: RefCell<Nat> = RefCell::new(Nat::from(1u64));
    
    static PLAYER_NFT_CANISTER: RefCell<Option<Principal>> = RefCell::new(None);
    static GAME_TOKEN_CANISTER: RefCell<Option<Principal>> = RefCell::new(None);
}

// Player management
#[update]
async fn register_player(username: String) -> Result<(), String> {
    let caller = caller();
    
    let player = Player {
        id: caller,
        username,
        level: 1,
        experience: 0,
        wins: 0,
        losses: 0,
        deck: Vec::new(),
        active_deck: Vec::new(),
    };

    PLAYERS.with(|players| {
        players.borrow_mut().insert(caller, player);
    });

    Ok(())
}

#[update]
async fn update_player_deck(deck: Vec<Nat>) -> Result<(), String> {
    let caller = caller();
    
    if deck.len() > 20 {
        return Err("Deck cannot have more than 20 cards".to_string());
    }

    // Verify player owns all cards
    for card_id in &deck {
        let owns_card = verify_card_ownership(caller, card_id.clone()).await?;
        if !owns_card {
            return Err(format!("Player does not own card {}", card_id));
        }
    }

    PLAYERS.with(|players| {
        let mut players = players.borrow_mut();
        if let Some(mut player) = players.get(&caller) {
            player.deck = deck;
            players.insert(caller, player);
            Ok(())
        } else {
            Err("Player not found".to_string())
        }
    })
}

#[update]
async fn set_active_deck(active_deck: Vec<Nat>) -> Result<(), String> {
    let caller = caller();
    
    if active_deck.len() != 5 {
        return Err("Active deck must have exactly 5 cards".to_string());
    }

    PLAYERS.with(|players| {
        let mut players = players.borrow_mut();
        if let Some(mut player) = players.get(&caller) {
            // Verify all cards are in player's deck
            for card_id in &active_deck {
                if !player.deck.contains(card_id) {
                    return Err(format!("Card {} not in player's deck", card_id));
                }
            }
            
            player.active_deck = active_deck;
            players.insert(caller, player);
            Ok(())
        } else {
            Err("Player not found".to_string())
        }
    })
}

async fn verify_card_ownership(player: Principal, card_id: Nat) -> Result<bool, String> {
    let nft_canister = PLAYER_NFT_CANISTER.with(|canister| *canister.borrow())
        .ok_or("Player NFT canister not set")?;

    let result: Result<(Vec<Option<Principal>>,), _> = ic_cdk::call(
        nft_canister,
        "icrc7_owner_of",
        (vec![card_id],),
    ).await;

    match result {
        Ok((owners,)) => {
            Ok(owners.get(0).map_or(false, |owner| {
                owner.map_or(false, |p| p == player)
            }))
        }
        Err(_) => Ok(false),
    }
}

// Match management
#[update]
async fn create_match(args: CreateMatchArgs) -> Result<Nat, String> {
    let caller = caller();
    
    // Verify player is registered
    let player = PLAYERS.with(|players| players.borrow().get(&caller))
        .ok_or("Player not registered")?;

    if args.deck.len() != 5 {
        return Err("Deck must have exactly 5 cards".to_string());
    }

    let match_id = NEXT_MATCH_ID.with(|id| {
        let current = id.borrow().clone();
        *id.borrow_mut() = current.clone() + Nat::from(1u64);
        current
    });

    let game_match = GameMatch {
        id: match_id.clone(),
        player1: caller,
        player2: Principal::anonymous(), // Will be set when someone joins
        player1_deck: args.deck,
        player2_deck: Vec::new(),
        status: MatchStatus::WaitingForPlayer,
        current_turn: caller,
        turn_number: 0,
        winner: None,
        start_time: ic_cdk::api::time(),
        last_move_time: ic_cdk::api::time(),
        moves: Vec::new(),
    };

    MATCHES.with(|matches| {
        matches.borrow_mut().insert(match_id.clone(), game_match);
    });

    Ok(match_id)
}

#[update]
async fn join_match(args: JoinMatchArgs) -> Result<(), String> {
    let caller = caller();
    
    if args.deck.len() != 5 {
        return Err("Deck must have exactly 5 cards".to_string());
    }

    MATCHES.with(|matches| {
        let mut matches = matches.borrow_mut();
        if let Some(mut game_match) = matches.get(&args.match_id) {
            if !matches!(game_match.status, MatchStatus::WaitingForPlayer) {
                return Err("Match is not waiting for players".to_string());
            }

            if game_match.player1 == caller {
                return Err("Cannot join your own match".to_string());
            }

            game_match.player2 = caller;
            game_match.player2_deck = args.deck;
            game_match.status = MatchStatus::Active;
            
            matches.insert(args.match_id, game_match);
            Ok(())
        } else {
            Err("Match not found".to_string())
        }
    })
}

#[update]
async fn make_move(args: MakeMoveArgs) -> Result<(), String> {
    let caller = caller();
    
    MATCHES.with(|matches| {
        let mut matches = matches.borrow_mut();
        if let Some(mut game_match) = matches.get(&args.match_id) {
            // Verify it's the player's turn
            if game_match.current_turn != caller {
                return Err("Not your turn".to_string());
            }

            if !matches!(game_match.status, MatchStatus::Active) {
                return Err("Match is not active".to_string());
            }

            // Process the move
            let game_move = GameMove {
                player: caller,
                move_type: args.move_type.clone(),
                card_id: args.card_id,
                target_card_id: args.target_card_id,
                timestamp: ic_cdk::api::time(),
            };

            game_match.moves.push(game_move);
            game_match.last_move_time = ic_cdk::api::time();

            // Handle different move types
            match args.move_type {
                MoveType::EndTurn => {
                    game_match.current_turn = if game_match.current_turn == game_match.player1 {
                        game_match.player2
                    } else {
                        game_match.player1
                    };
                    game_match.turn_number += 1;
                }
                MoveType::PlayCard => {
                    // Implementation for playing a card
                }
                MoveType::Attack => {
                    // Implementation for attacking
                }
                MoveType::UseSpecialAbility => {
                    // Implementation for special abilities
                }
            }

            matches.insert(args.match_id, game_match);
            Ok(())
        } else {
            Err("Match not found".to_string())
        }
    })
}

#[update]
async fn end_match(match_id: Nat, winner: Principal) -> Result<(), String> {
    MATCHES.with(|matches| {
        let mut matches = matches.borrow_mut();
        if let Some(mut game_match) = matches.get(&match_id) {
            game_match.status = MatchStatus::Finished;
            game_match.winner = Some(winner);
            
            // Update player stats
            update_player_stats(game_match.player1, winner == game_match.player1);
            update_player_stats(game_match.player2, winner == game_match.player2);
            
            matches.insert(match_id, game_match);
            Ok(())
        } else {
            Err("Match not found".to_string())
        }
    })
}

fn update_player_stats(player_id: Principal, won: bool) {
    PLAYERS.with(|players| {
        let mut players = players.borrow_mut();
        if let Some(mut player) = players.get(&player_id) {
            if won {
                player.wins += 1;
                player.experience += 100;
            } else {
                player.losses += 1;
                player.experience += 50;
            }
            
            // Level up logic
            let required_exp = player.level * 1000;
            if player.experience >= required_exp as u64 {
                player.level += 1;
            }
            
            players.insert(player_id, player);
        }
    });
}

// Query functions
#[query]
fn get_player(player_id: Principal) -> Option<Player> {
    PLAYERS.with(|players| players.borrow().get(&player_id))
}

#[query]
fn get_match(match_id: Nat) -> Option<GameMatch> {
    MATCHES.with(|matches| matches.borrow().get(&match_id))
}

#[query]
fn get_active_matches() -> Vec<GameMatch> {
    MATCHES.with(|matches| {
        matches
            .borrow()
            .iter()
            .filter(|(_, game_match)| matches!(game_match.status, MatchStatus::Active))
            .map(|(_, game_match)| game_match)
            .collect()
    })
}

#[query]
fn get_waiting_matches() -> Vec<GameMatch> {
    MATCHES.with(|matches| {
        matches
            .borrow()
            .iter()
            .filter(|(_, game_match)| matches!(game_match.status, MatchStatus::WaitingForPlayer))
            .map(|(_, game_match)| game_match)
            .collect()
    })
}

#[query]
fn get_player_matches(player_id: Principal) -> Vec<GameMatch> {
    MATCHES.with(|matches| {
        matches
            .borrow()
            .iter()
            .filter(|(_, game_match)| {
                game_match.player1 == player_id || game_match.player2 == player_id
            })
            .map(|(_, game_match)| game_match)
            .collect()
    })
}

// Configuration
#[update]
async fn set_player_nft_canister(canister_id: Principal) -> Result<(), String> {
    PLAYER_NFT_CANISTER.with(|canister| {
        *canister.borrow_mut() = Some(canister_id);
    });
    Ok(())
}

#[update]
async fn set_game_token_canister(canister_id: Principal) -> Result<(), String> {
    GAME_TOKEN_CANISTER.with(|canister| {
        *canister.borrow_mut() = Some(canister_id);
    });
    Ok(())
}

// Reward system
#[update]
async fn reward_player(player_id: Principal, tokens: Nat) -> Result<(), String> {
    let game_token_canister = GAME_TOKEN_CANISTER.with(|canister| *canister.borrow())
        .ok_or("Game token canister not set")?;

    let _mint_result: Result<(Result<(), String>,), _> = ic_cdk::call(
        game_token_canister,
        "mint_game_tokens",
        (player_id, tokens),
    ).await;

    Ok(())
} 