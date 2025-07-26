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
pub struct AuctionData {
    pub id: Nat,
    pub seller: Principal,
    pub nft_canister: Principal,
    pub token_id: Nat,
    pub starting_price: Nat,
    pub current_highest_bid: Nat,
    pub highest_bidder: Option<Principal>,
    pub end_time: u64,
    pub status: AuctionStatus,
    pub factory_canister: Principal,
}

#[derive(CandidType, Deserialize, Clone, Serialize)]
pub enum AuctionStatus {
    Active,
    Ended,
    Cancelled,
}

#[derive(CandidType, Deserialize)]
pub struct BidArgs {
    pub amount: Nat,
}

thread_local! {
    static AUCTION_DATA: RefCell<Option<AuctionData>> = RefCell::new(None);
    
    static BIDS: RefCell<StableBTreeMap<Principal, Nat, Memory>> = RefCell::new(
        StableBTreeMap::init(
            MEMORY_MANAGER.with(|m| m.borrow().get(MemoryId::new(0))),
        )
    );

    static MEMORY_MANAGER: RefCell<MemoryManager<DefaultMemoryImpl>> =
        RefCell::new(MemoryManager::init(DefaultMemoryImpl::default()));
        
    static END_TIMER: RefCell<Option<ic_cdk_timers::TimerId>> = RefCell::new(None);
}

#[update]
async fn init_auction(
    id: Nat,
    seller: Principal,
    nft_canister: Principal,
    token_id: Nat,
    starting_price: Nat,
    end_time: u64,
    factory_canister: Principal,
) -> Result<(), String> {
    let auction_data = AuctionData {
        id,
        seller,
        nft_canister,
        token_id,
        starting_price: starting_price.clone(),
        current_highest_bid: starting_price,
        highest_bidder: None,
        end_time,
        status: AuctionStatus::Active,
        factory_canister,
    };

    AUCTION_DATA.with(|data| {
        *data.borrow_mut() = Some(auction_data);
    });

    // Set timer to end auction
    let duration = Duration::from_nanos(end_time - ic_cdk::api::time());
    let timer_id = set_timer(duration, || {
        ic_cdk::spawn(end_auction())
    });
    
    END_TIMER.with(|timer| {
        *timer.borrow_mut() = Some(timer_id);
    });

    Ok(())
}

#[update]
async fn place_bid(args: BidArgs) -> Result<(), String> {
    let caller = caller();
    
    let auction_data = AUCTION_DATA.with(|data| {
        data.borrow().clone()
    }).ok_or("Auction not initialized")?;

    // Check if auction is active
    if !matches!(auction_data.status, AuctionStatus::Active) {
        return Err("Auction is not active".to_string());
    }

    // Check if auction has ended
    if ic_cdk::api::time() >= auction_data.end_time {
        return Err("Auction has ended".to_string());
    }

    // Check if bid is higher than current highest
    if args.amount <= auction_data.current_highest_bid {
        return Err("Bid must be higher than current highest bid".to_string());
    }

    // Store bid
    BIDS.with(|bids| {
        bids.borrow_mut().insert(caller, args.amount.clone());
    });

    // Update auction data
    AUCTION_DATA.with(|data| {
        if let Some(ref mut auction) = *data.borrow_mut() {
            auction.current_highest_bid = args.amount;
            auction.highest_bidder = Some(caller);
        }
    });

    // Notify factory about bid update
    let _ = ic_cdk::call::<(Nat, Nat, Principal), (Result<(), String>,)>(
        auction_data.factory_canister,
        "update_auction_bid",
        (auction_data.id, args.amount, caller),
    ).await;

    Ok(())
}

#[update]
async fn end_auction() -> Result<(), String> {
    let mut auction_data = AUCTION_DATA.with(|data| {
        data.borrow().clone()
    }).ok_or("Auction not initialized")?;

    if !matches!(auction_data.status, AuctionStatus::Active) {
        return Err("Auction is not active".to_string());
    }

    auction_data.status = AuctionStatus::Ended;
    
    AUCTION_DATA.with(|data| {
        *data.borrow_mut() = Some(auction_data.clone());
    });

    // Clear the timer
    END_TIMER.with(|timer| {
        if let Some(timer_id) = timer.borrow_mut().take() {
            clear_timer(timer_id);
        }
    });

    // If there's a winning bidder, transfer NFT
    if let Some(winner) = auction_data.highest_bidder {
        let _ = transfer_nft_to_winner(auction_data.clone(), winner).await;
    }

    // Notify factory about auction end
    let _ = ic_cdk::call::<(Nat, AuctionStatus), (Result<(), String>,)>(
        auction_data.factory_canister,
        "update_auction_status",
        (auction_data.id, AuctionStatus::Ended),
    ).await;

    Ok(())
}

async fn transfer_nft_to_winner(auction: AuctionData, winner: Principal) -> Result<(), String> {
    // Call NFT canister to transfer token
    // This is a simplified version - in reality, you'd need proper ICRC-7 transfer
    let transfer_args = (
        auction.seller,
        winner,
        auction.token_id,
    );

    let _result: Result<(Result<(), String>,), _> = ic_cdk::call(
        auction.nft_canister,
        "transfer_from",
        transfer_args,
    ).await;

    Ok(())
}

#[update]
async fn cancel_auction() -> Result<(), String> {
    let caller = caller();
    
    let mut auction_data = AUCTION_DATA.with(|data| {
        data.borrow().clone()
    }).ok_or("Auction not initialized")?;

    // Only seller can cancel
    if caller != auction_data.seller {
        return Err("Only seller can cancel auction".to_string());
    }

    // Can only cancel if no bids
    if auction_data.highest_bidder.is_some() {
        return Err("Cannot cancel auction with existing bids".to_string());
    }

    auction_data.status = AuctionStatus::Cancelled;
    
    AUCTION_DATA.with(|data| {
        *data.borrow_mut() = Some(auction_data.clone());
    });

    // Clear the timer
    END_TIMER.with(|timer| {
        if let Some(timer_id) = timer.borrow_mut().take() {
            clear_timer(timer_id);
        }
    });

    // Notify factory
    let _ = ic_cdk::call::<(Nat, AuctionStatus), (Result<(), String>,)>(
        auction_data.factory_canister,
        "update_auction_status",
        (auction_data.id, AuctionStatus::Cancelled),
    ).await;

    Ok(())
}

#[query]
fn get_auction_info() -> Option<AuctionData> {
    AUCTION_DATA.with(|data| data.borrow().clone())
}

#[query]
fn get_bid(bidder: Principal) -> Option<Nat> {
    BIDS.with(|bids| bids.borrow().get(&bidder))
}

#[query]
fn get_all_bids() -> Vec<(Principal, Nat)> {
    BIDS.with(|bids| {
        bids.borrow().iter().collect()
    })
} 