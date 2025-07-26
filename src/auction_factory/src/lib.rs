use candid::{CandidType, Deserialize, Nat, Principal};
use ic_cdk::{caller, query, update};
use ic_stable_structures::memory_manager::{MemoryId, MemoryManager, VirtualMemory};
use ic_stable_structures::{DefaultMemoryImpl, StableBTreeMap};
use serde::Serialize;
use std::cell::RefCell;

type Memory = VirtualMemory<DefaultMemoryImpl>;

#[derive(CandidType, Deserialize, Clone, Serialize)]
pub struct AuctionInfo {
    pub id: Nat,
    pub canister_id: Principal,
    pub seller: Principal,
    pub nft_canister: Principal,
    pub token_id: Nat,
    pub starting_price: Nat,
    pub current_highest_bid: Nat,
    pub highest_bidder: Option<Principal>,
    pub end_time: u64,
    pub status: AuctionStatus,
    pub created_at: u64,
}

#[derive(CandidType, Deserialize, Clone, Serialize)]
pub enum AuctionStatus {
    Active,
    Ended,
    Cancelled,
}

#[derive(CandidType, Deserialize)]
pub struct CreateAuctionArgs {
    pub nft_canister: Principal,
    pub token_id: Nat,
    pub starting_price: Nat,
    pub duration_hours: u64,
}

thread_local! {
    static MEMORY_MANAGER: RefCell<MemoryManager<DefaultMemoryImpl>> =
        RefCell::new(MemoryManager::init(DefaultMemoryImpl::default()));

    static AUCTIONS: RefCell<StableBTreeMap<Nat, AuctionInfo, Memory>> = RefCell::new(
        StableBTreeMap::init(
            MEMORY_MANAGER.with(|m| m.borrow().get(MemoryId::new(0))),
        )
    );

    static NEXT_AUCTION_ID: RefCell<Nat> = RefCell::new(Nat::from(1u64));
    
    static AUCTION_TEMPLATE_WASM: RefCell<Vec<u8>> = RefCell::new(Vec::new());
}

#[update]
async fn create_auction(args: CreateAuctionArgs) -> Result<Nat, String> {
    let caller = caller();
    let auction_id = NEXT_AUCTION_ID.with(|id| {
        let current = id.borrow().clone();
        *id.borrow_mut() = current.clone() + Nat::from(1u64);
        current
    });

    // Create new auction canister
    let canister_id = create_auction_canister(auction_id.clone()).await?;
    
    let auction_info = AuctionInfo {
        id: auction_id.clone(),
        canister_id,
        seller: caller,
        nft_canister: args.nft_canister,
        token_id: args.token_id,
        starting_price: args.starting_price,
        current_highest_bid: Nat::from(0u64),
        highest_bidder: None,
        end_time: ic_cdk::api::time() + (args.duration_hours * 60 * 60 * 1_000_000_000),
        status: AuctionStatus::Active,
        created_at: ic_cdk::api::time(),
    };

    AUCTIONS.with(|auctions| {
        auctions.borrow_mut().insert(auction_id.clone(), auction_info);
    });

    Ok(auction_id)
}

async fn create_auction_canister(auction_id: Nat) -> Result<Principal, String> {
    use ic_cdk::api::management_canister::main::{
        create_canister, install_code, CanisterSettings, CreateCanisterArgument,
        InstallCodeArgument, CanisterInstallMode,
    };

    // Create canister with cycles
    let create_args = CreateCanisterArgument {
        settings: Some(CanisterSettings {
            controllers: Some(vec![ic_cdk::id()]),
            compute_allocation: None,
            memory_allocation: None,
            freezing_threshold: None,
            reserved_cycles_limit: None,
        }),
    };

    let (canister_id,) = create_canister(create_args, 2_000_000_000_000u128)
        .await
        .map_err(|e| format!("Failed to create canister: {:?}", e))?;

    // Install auction contract code
    let wasm_module = AUCTION_TEMPLATE_WASM.with(|wasm| wasm.borrow().clone());
    
    let install_args = InstallCodeArgument {
        mode: CanisterInstallMode::Install,
        canister_id,
        wasm_module,
        arg: candid::encode_args((auction_id,)).unwrap(),
    };

    install_code(install_args)
        .await
        .map_err(|e| format!("Failed to install code: {:?}", e))?;

    Ok(canister_id)
}

#[query]
fn get_auction(auction_id: Nat) -> Option<AuctionInfo> {
    AUCTIONS.with(|auctions| auctions.borrow().get(&auction_id))
}

#[query]
fn get_active_auctions() -> Vec<AuctionInfo> {
    AUCTIONS.with(|auctions| {
        auctions
            .borrow()
            .iter()
            .filter(|(_, auction)| matches!(auction.status, AuctionStatus::Active))
            .map(|(_, auction)| auction)
            .collect()
    })
}

#[query]
fn get_auctions_by_seller(seller: Principal) -> Vec<AuctionInfo> {
    AUCTIONS.with(|auctions| {
        auctions
            .borrow()
            .iter()
            .filter(|(_, auction)| auction.seller == seller)
            .map(|(_, auction)| auction)
            .collect()
    })
}

#[update]
fn update_auction_status(auction_id: Nat, status: AuctionStatus) -> Result<(), String> {
    AUCTIONS.with(|auctions| {
        let mut auctions = auctions.borrow_mut();
        match auctions.get(&auction_id) {
            Some(mut auction) => {
                auction.status = status;
                auctions.insert(auction_id, auction);
                Ok(())
            }
            None => Err("Auction not found".to_string()),
        }
    })
}

#[update]
fn update_auction_bid(
    auction_id: Nat,
    highest_bid: Nat,
    highest_bidder: Principal,
) -> Result<(), String> {
    AUCTIONS.with(|auctions| {
        let mut auctions = auctions.borrow_mut();
        match auctions.get(&auction_id) {
            Some(mut auction) => {
                auction.current_highest_bid = highest_bid;
                auction.highest_bidder = Some(highest_bidder);
                auctions.insert(auction_id, auction);
                Ok(())
            }
            None => Err("Auction not found".to_string()),
        }
    })
}

#[update]
async fn set_auction_template_wasm(wasm: Vec<u8>) -> Result<(), String> {
    // Only canister controllers can set the template
    AUCTION_TEMPLATE_WASM.with(|template| {
        *template.borrow_mut() = wasm;
    });
    Ok(())
} 