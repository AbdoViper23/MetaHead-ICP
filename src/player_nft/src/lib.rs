use candid::{CandidType, Deserialize, Nat, Principal};
use ic_cdk::{caller, id, query, update};
use ic_stable_structures::memory_manager::{MemoryId, MemoryManager, VirtualMemory};
use ic_stable_structures::{DefaultMemoryImpl, StableBTreeMap};
use serde::Serialize;
use std::cell::RefCell;
use std::collections::HashMap;

type Memory = VirtualMemory<DefaultMemoryImpl>;

// ICRC-7 NFT types
#[derive(CandidType, Deserialize, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub struct Account {
    pub owner: Principal,
    pub subaccount: Option<[u8; 32]>,
}

#[derive(CandidType, Deserialize, Serialize, Clone)]
pub struct PlayerCard {
    pub id: Nat,
    pub name: String,
    pub rarity: String, // Common, Rare, Epic, Legendary
    pub attack: u32,
    pub defense: u32,
    pub speed: u32,
    pub special_ability: String,
    pub image_url: String,
}

#[derive(CandidType, Deserialize)]
pub struct TransferArgs {
    pub spender_subaccount: Option<[u8; 32]>,
    pub from: Account,
    pub to: Account,
    pub token_id: Nat,
    pub memo: Option<Vec<u8>>,
    pub created_at_time: Option<u64>,
}

#[derive(CandidType, Deserialize)]
pub enum TransferError {
    Unauthorized,
    TooOld,
    CreatedInFuture,
    Duplicate { duplicate_of: Nat },
    TemporarilyUnavailable,
    GenericError { error_code: Nat, message: String },
}

// Collection metadata
const COLLECTION_NAME: &str = "MetaHead Player Cards";
const COLLECTION_SYMBOL: &str = "MHPC";

thread_local! {
    static MEMORY_MANAGER: RefCell<MemoryManager<DefaultMemoryImpl>> =
        RefCell::new(MemoryManager::init(DefaultMemoryImpl::default()));

    static TOKENS: RefCell<StableBTreeMap<Nat, PlayerCard, Memory>> = RefCell::new(
        StableBTreeMap::init(
            MEMORY_MANAGER.with(|m| m.borrow().get(MemoryId::new(0))),
        )
    );

    static OWNERS: RefCell<StableBTreeMap<Nat, Account, Memory>> = RefCell::new(
        StableBTreeMap::init(
            MEMORY_MANAGER.with(|m| m.borrow().get(MemoryId::new(1))),
        )
    );

    static NEXT_TOKEN_ID: RefCell<Nat> = RefCell::new(Nat::from(1u64));
}

#[query]
fn icrc7_collection_metadata() -> Vec<(String, candid::CandidType)> {
    vec![
        ("icrc7:name".to_string(), candid::CandidType::Text(COLLECTION_NAME.to_string())),
        ("icrc7:symbol".to_string(), candid::CandidType::Text(COLLECTION_SYMBOL.to_string())),
        ("icrc7:description".to_string(), candid::CandidType::Text("Player cards for MetaHead game".to_string())),
    ]
}

#[query]
fn icrc7_name() -> String {
    COLLECTION_NAME.to_string()
}

#[query]
fn icrc7_symbol() -> String {
    COLLECTION_SYMBOL.to_string()
}

#[query]
fn icrc7_total_supply() -> Nat {
    TOKENS.with(|tokens| {
        Nat::from(tokens.borrow().len() as u64)
    })
}

#[query]
fn icrc7_tokens(prev: Option<Nat>, take: Option<Nat>) -> Vec<Nat> {
    TOKENS.with(|tokens| {
        let tokens = tokens.borrow();
        let start = prev.unwrap_or(Nat::from(0u64));
        let limit = take.unwrap_or(Nat::from(100u64));
        
        tokens
            .iter()
            .skip(start.0.to_u64_digits()[0] as usize)
            .take(limit.0.to_u64_digits()[0] as usize)
            .map(|(id, _)| id)
            .collect()
    })
}

#[query]
fn icrc7_owner_of(token_ids: Vec<Nat>) -> Vec<Option<Account>> {
    OWNERS.with(|owners| {
        let owners = owners.borrow();
        token_ids
            .iter()
            .map(|id| owners.get(id))
            .collect()
    })
}

#[query]
fn icrc7_balance_of(accounts: Vec<Account>) -> Vec<Nat> {
    OWNERS.with(|owners| {
        let owners = owners.borrow();
        accounts
            .iter()
            .map(|account| {
                let count = owners
                    .iter()
                    .filter(|(_, owner)| *owner == *account)
                    .count();
                Nat::from(count as u64)
            })
            .collect()
    })
}

#[query]
fn icrc7_tokens_of(account: Account, prev: Option<Nat>, take: Option<Nat>) -> Vec<Nat> {
    OWNERS.with(|owners| {
        let owners = owners.borrow();
        let start = prev.unwrap_or(Nat::from(0u64));
        let limit = take.unwrap_or(Nat::from(100u64));
        
        owners
            .iter()
            .filter(|(_, owner)| *owner == account)
            .skip(start.0.to_u64_digits()[0] as usize)
            .take(limit.0.to_u64_digits()[0] as usize)
            .map(|(id, _)| id)
            .collect()
    })
}

#[update]
fn icrc7_transfer(args: Vec<TransferArgs>) -> Vec<Option<TransferError>> {
    let caller = caller();
    
    args.iter()
        .map(|arg| {
            // Check ownership
            let owner = OWNERS.with(|owners| owners.borrow().get(&arg.token_id));
            
            match owner {
                Some(current_owner) if current_owner.owner == caller => {
                    // Transfer the token
                    OWNERS.with(|owners| {
                        owners.borrow_mut().insert(arg.token_id.clone(), arg.to.clone());
                    });
                    None
                }
                Some(_) => Some(TransferError::Unauthorized),
                None => Some(TransferError::GenericError {
                    error_code: Nat::from(404u64),
                    message: "Token not found".to_string(),
                }),
            }
        })
        .collect()
}

// Game-specific functions
#[query]
fn get_player_card(token_id: Nat) -> Option<PlayerCard> {
    TOKENS.with(|tokens| tokens.borrow().get(&token_id))
}

#[update]
async fn mint_player_card(
    to: Account,
    name: String,
    rarity: String,
    attack: u32,
    defense: u32,
    speed: u32,
    special_ability: String,
    image_url: String,
) -> Result<Nat, String> {
    let caller = caller();
    
    // Only authorized minters can create cards
    if caller != id() {
        return Err("Unauthorized".to_string());
    }

    let token_id = NEXT_TOKEN_ID.with(|id| {
        let current = id.borrow().clone();
        *id.borrow_mut() = current.clone() + Nat::from(1u64);
        current
    });

    let card = PlayerCard {
        id: token_id.clone(),
        name,
        rarity,
        attack,
        defense,
        speed,
        special_ability,
        image_url,
    };

    TOKENS.with(|tokens| {
        tokens.borrow_mut().insert(token_id.clone(), card);
    });

    OWNERS.with(|owners| {
        owners.borrow_mut().insert(token_id.clone(), to);
    });

    Ok(token_id)
}

#[query]
fn get_player_cards_by_rarity(rarity: String) -> Vec<PlayerCard> {
    TOKENS.with(|tokens| {
        tokens
            .borrow()
            .iter()
            .filter(|(_, card)| card.rarity == rarity)
            .map(|(_, card)| card)
            .collect()
    })
} 