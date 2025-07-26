use candid::{CandidType, Deserialize, Nat, Principal};
use ic_cdk::{caller, query, update};
use ic_stable_structures::memory_manager::{MemoryId, MemoryManager, VirtualMemory};
use ic_stable_structures::{DefaultMemoryImpl, StableBTreeMap};
use serde::Serialize;
use sha2::{Digest, Sha256};
use std::cell::RefCell;

type Memory = VirtualMemory<DefaultMemoryImpl>;

#[derive(CandidType, Deserialize, Clone, Serialize)]
pub struct MysteryBox {
    pub id: Nat,
    pub box_type: BoxType,
    pub price: Nat,
    pub available_count: u32,
    pub total_count: u32,
    pub rarity_weights: Vec<RarityWeight>,
}

#[derive(CandidType, Deserialize, Clone, Serialize)]
pub enum BoxType {
    Common,
    Rare,
    Epic,
    Legendary,
}

#[derive(CandidType, Deserialize, Clone, Serialize)]
pub struct RarityWeight {
    pub rarity: String,
    pub weight: u32,
    pub cards: Vec<CardTemplate>,
}

#[derive(CandidType, Deserialize, Clone, Serialize)]
pub struct CardTemplate {
    pub name: String,
    pub attack: u32,
    pub defense: u32,
    pub speed: u32,
    pub special_ability: String,
    pub image_url: String,
}

#[derive(CandidType, Deserialize)]
pub struct OpenBoxArgs {
    pub box_id: Nat,
}

#[derive(CandidType, Deserialize, Clone, Serialize)]
pub struct BoxOpenResult {
    pub player_card_id: Nat,
    pub rarity: String,
    pub card_details: CardTemplate,
}

thread_local! {
    static MEMORY_MANAGER: RefCell<MemoryManager<DefaultMemoryImpl>> =
        RefCell::new(MemoryManager::init(DefaultMemoryImpl::default()));

    static MYSTERY_BOXES: RefCell<StableBTreeMap<Nat, MysteryBox, Memory>> = RefCell::new(
        StableBTreeMap::init(
            MEMORY_MANAGER.with(|m| m.borrow().get(MemoryId::new(0))),
        )
    );

    static NEXT_BOX_ID: RefCell<Nat> = RefCell::new(Nat::from(1u64));
    
    static PLAYER_NFT_CANISTER: RefCell<Option<Principal>> = RefCell::new(None);
    static GAME_TOKEN_CANISTER: RefCell<Option<Principal>> = RefCell::new(None);
}

#[update]
async fn create_mystery_box(
    box_type: BoxType,
    price: Nat,
    total_count: u32,
    rarity_weights: Vec<RarityWeight>,
) -> Result<Nat, String> {
    let box_id = NEXT_BOX_ID.with(|id| {
        let current = id.borrow().clone();
        *id.borrow_mut() = current.clone() + Nat::from(1u64);
        current
    });

    let mystery_box = MysteryBox {
        id: box_id.clone(),
        box_type,
        price,
        available_count: total_count,
        total_count,
        rarity_weights,
    };

    MYSTERY_BOXES.with(|boxes| {
        boxes.borrow_mut().insert(box_id.clone(), mystery_box);
    });

    Ok(box_id)
}

#[update]
async fn open_mystery_box(args: OpenBoxArgs) -> Result<BoxOpenResult, String> {
    let caller = caller();
    
    // Get mystery box
    let mut mystery_box = MYSTERY_BOXES.with(|boxes| {
        boxes.borrow().get(&args.box_id)
    }).ok_or("Mystery box not found")?;

    if mystery_box.available_count == 0 {
        return Err("No more boxes available".to_string());
    }

    // Check payment (simplified - should check game token balance)
    let game_token_canister = GAME_TOKEN_CANISTER.with(|canister| *canister.borrow())
        .ok_or("Game token canister not set")?;

    // Burn tokens for payment
    let _burn_result: Result<(Result<(), String>,), _> = ic_cdk::call(
        game_token_canister,
        "burn_game_tokens",
        (caller, mystery_box.price.clone()),
    ).await;

    // Generate random card
    let random_seed = get_random_seed().await?;
    let selected_card = select_random_card(&mystery_box, random_seed)?;

    // Mint NFT
    let player_nft_canister = PLAYER_NFT_CANISTER.with(|canister| *canister.borrow())
        .ok_or("Player NFT canister not set")?;

    let mint_result: Result<(Result<Nat, String>,), _> = ic_cdk::call(
        player_nft_canister,
        "mint_player_card",
        (
            caller,
            selected_card.card_details.name.clone(),
            selected_card.rarity.clone(),
            selected_card.card_details.attack,
            selected_card.card_details.defense,
            selected_card.card_details.speed,
            selected_card.card_details.special_ability.clone(),
            selected_card.card_details.image_url.clone(),
        ),
    ).await;

    let token_id = mint_result
        .map_err(|e| format!("Failed to call NFT canister: {:?}", e))?
        .0
        .map_err(|e| format!("Failed to mint NFT: {}", e))?;

    // Update box count
    mystery_box.available_count -= 1;
    MYSTERY_BOXES.with(|boxes| {
        boxes.borrow_mut().insert(args.box_id, mystery_box);
    });

    Ok(BoxOpenResult {
        player_card_id: token_id,
        rarity: selected_card.rarity,
        card_details: selected_card.card_details,
    })
}

async fn get_random_seed() -> Result<[u8; 32], String> {
    let (random_bytes,): (Vec<u8>,) = ic_cdk::call(
        Principal::management_canister(),
        "raw_rand",
        (),
    )
    .await
    .map_err(|e| format!("Failed to get randomness: {:?}", e))?;

    if random_bytes.len() < 32 {
        return Err("Insufficient random bytes".to_string());
    }

    let mut seed = [0u8; 32];
    seed.copy_from_slice(&random_bytes[..32]);
    Ok(seed)
}

fn select_random_card(mystery_box: &MysteryBox, seed: [u8; 32]) -> Result<BoxOpenResult, String> {
    // Calculate total weight
    let total_weight: u32 = mystery_box.rarity_weights.iter().map(|rw| rw.weight).sum();
    
    // Generate random number based on seed
    let mut hasher = Sha256::new();
    hasher.update(&seed);
    hasher.update(&mystery_box.id.0.to_be_bytes());
    let hash = hasher.finalize();
    
    let random_value = u32::from_be_bytes([hash[0], hash[1], hash[2], hash[3]]) % total_weight;
    
    // Select rarity based on weight
    let mut current_weight = 0;
    for rarity_weight in &mystery_box.rarity_weights {
        current_weight += rarity_weight.weight;
        if random_value < current_weight {
            if rarity_weight.cards.is_empty() {
                return Err("No cards available for selected rarity".to_string());
            }
            
            // Select random card from this rarity
            let card_index = (random_value % rarity_weight.cards.len() as u32) as usize;
            let selected_card = &rarity_weight.cards[card_index];
            
            return Ok(BoxOpenResult {
                player_card_id: Nat::from(0u64), // Will be set after minting
                rarity: rarity_weight.rarity.clone(),
                card_details: selected_card.clone(),
            });
        }
    }
    
    Err("Failed to select card".to_string())
}

#[query]
fn get_mystery_box(box_id: Nat) -> Option<MysteryBox> {
    MYSTERY_BOXES.with(|boxes| boxes.borrow().get(&box_id))
}

#[query]
fn get_all_mystery_boxes() -> Vec<MysteryBox> {
    MYSTERY_BOXES.with(|boxes| {
        boxes.borrow().iter().map(|(_, box_data)| box_data).collect()
    })
}

#[query]
fn get_available_boxes() -> Vec<MysteryBox> {
    MYSTERY_BOXES.with(|boxes| {
        boxes
            .borrow()
            .iter()
            .filter(|(_, box_data)| box_data.available_count > 0)
            .map(|(_, box_data)| box_data)
            .collect()
    })
}

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

// Helper function to create default card templates
pub fn create_default_card_templates() -> Vec<RarityWeight> {
    vec![
        RarityWeight {
            rarity: "Common".to_string(),
            weight: 50,
            cards: vec![
                CardTemplate {
                    name: "Warrior".to_string(),
                    attack: 100,
                    defense: 80,
                    speed: 60,
                    special_ability: "Strike".to_string(),
                    image_url: "https://example.com/warrior.png".to_string(),
                },
                CardTemplate {
                    name: "Archer".to_string(),
                    attack: 80,
                    defense: 60,
                    speed: 100,
                    special_ability: "Precise Shot".to_string(),
                    image_url: "https://example.com/archer.png".to_string(),
                },
            ],
        },
        RarityWeight {
            rarity: "Rare".to_string(),
            weight: 30,
            cards: vec![
                CardTemplate {
                    name: "Mage".to_string(),
                    attack: 120,
                    defense: 70,
                    speed: 80,
                    special_ability: "Fireball".to_string(),
                    image_url: "https://example.com/mage.png".to_string(),
                },
            ],
        },
        RarityWeight {
            rarity: "Epic".to_string(),
            weight: 15,
            cards: vec![
                CardTemplate {
                    name: "Dragon Knight".to_string(),
                    attack: 150,
                    defense: 120,
                    speed: 90,
                    special_ability: "Dragon Breath".to_string(),
                    image_url: "https://example.com/dragon_knight.png".to_string(),
                },
            ],
        },
        RarityWeight {
            rarity: "Legendary".to_string(),
            weight: 5,
            cards: vec![
                CardTemplate {
                    name: "Ancient Guardian".to_string(),
                    attack: 200,
                    defense: 180,
                    speed: 120,
                    special_ability: "Time Stop".to_string(),
                    image_url: "https://example.com/ancient_guardian.png".to_string(),
                },
            ],
        },
    ]
} 