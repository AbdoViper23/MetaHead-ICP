use candid::{CandidType, Deserialize, Nat, Principal};
use ic_cdk::api::management_canister::main::raw_rand;
use ic_cdk::{caller, id, query, update};
use ic_stable_structures::memory_manager::{MemoryId, MemoryManager, VirtualMemory};
use ic_stable_structures::{DefaultMemoryImpl, StableBTreeMap};
use serde::Serialize;
use std::cell::RefCell;

type Memory = VirtualMemory<DefaultMemoryImpl>;

// ICRC-1 Token types
#[derive(CandidType, Deserialize, Clone)]
pub struct Account {
    pub owner: Principal,
    pub subaccount: Option<[u8; 32]>,
}

#[derive(CandidType, Deserialize)]
pub struct TransferArgs {
    pub from_subaccount: Option<[u8; 32]>,
    pub to: Account,
    pub amount: Nat,
    pub fee: Option<Nat>,
    pub memo: Option<Vec<u8>>,
    pub created_at_time: Option<u64>,
}

#[derive(CandidType, Deserialize)]
pub enum TransferError {
    BadFee { expected_fee: Nat },
    BadBurn { min_burn_amount: Nat },
    InsufficientFunds { balance: Nat },
    TooOld,
    CreatedInFuture,
    Duplicate { duplicate_of: Nat },
    TemporarilyUnavailable,
    GenericError { error_code: Nat, message: String },
}

// Token metadata
const TOKEN_NAME: &str = "GameToken";
const TOKEN_SYMBOL: &str = "GAME";
const TOKEN_DECIMALS: u8 = 8;
const TOKEN_FEE: u64 = 10_000; // 0.0001 tokens

thread_local! {
    static MEMORY_MANAGER: RefCell<MemoryManager<DefaultMemoryImpl>> =
        RefCell::new(MemoryManager::init(DefaultMemoryImpl::default()));

    static BALANCES: RefCell<StableBTreeMap<Account, Nat, Memory>> = RefCell::new(
        StableBTreeMap::init(
            MEMORY_MANAGER.with(|m| m.borrow().get(MemoryId::new(0))),
        )
    );

    static TOTAL_SUPPLY: RefCell<Nat> = RefCell::new(Nat::from(0u64));
}

#[query]
fn icrc1_name() -> String {
    TOKEN_NAME.to_string()
}

#[query]
fn icrc1_symbol() -> String {
    TOKEN_SYMBOL.to_string()
}

#[query]
fn icrc1_decimals() -> u8 {
    TOKEN_DECIMALS
}

#[query]
fn icrc1_fee() -> Nat {
    Nat::from(TOKEN_FEE)
}

#[query]
fn icrc1_total_supply() -> Nat {
    TOTAL_SUPPLY.with(|supply| supply.borrow().clone())
}

#[query]
fn icrc1_minting_account() -> Option<Account> {
    Some(Account {
        owner: id(),
        subaccount: None,
    })
}

#[query]
fn icrc1_balance_of(account: Account) -> Nat {
    BALANCES.with(|balances| {
        balances.borrow().get(&account).unwrap_or(Nat::from(0u64))
    })
}

#[update]
fn icrc1_transfer(args: TransferArgs) -> Result<Nat, TransferError> {
    let caller = caller();
    let from_account = Account {
        owner: caller,
        subaccount: args.from_subaccount,
    };

    // Check balance
    let balance = icrc1_balance_of(from_account.clone());
    let amount_with_fee = args.amount.clone() + Nat::from(TOKEN_FEE);
    
    if balance < amount_with_fee {
        return Err(TransferError::InsufficientFunds { balance });
    }

    // Perform transfer
    BALANCES.with(|balances| {
        let mut balances = balances.borrow_mut();
        
        // Deduct from sender
        let new_from_balance = balance - amount_with_fee;
        if new_from_balance == Nat::from(0u64) {
            balances.remove(&from_account);
        } else {
            balances.insert(from_account, new_from_balance);
        }
        
        // Add to recipient
        let to_balance = balances.get(&args.to).unwrap_or(Nat::from(0u64));
        balances.insert(args.to, to_balance + args.amount);
    });

    // Return transaction ID (simplified)
    Ok(Nat::from(ic_cdk::api::time()))
}

// Game-specific functions
#[update]
async fn mint_game_tokens(to: Account, amount: Nat) -> Result<(), String> {
    let caller = caller();
    
    // Only the game engine can mint tokens
    if caller != id() {
        return Err("Unauthorized".to_string());
    }

    BALANCES.with(|balances| {
        let mut balances = balances.borrow_mut();
        let current_balance = balances.get(&to).unwrap_or(Nat::from(0u64));
        balances.insert(to, current_balance + amount.clone());
    });

    TOTAL_SUPPLY.with(|supply| {
        let mut supply = supply.borrow_mut();
        *supply = supply.clone() + amount;
    });

    Ok(())
}

#[update]
async fn burn_game_tokens(from: Account, amount: Nat) -> Result<(), String> {
    let balance = icrc1_balance_of(from.clone());
    
    if balance < amount {
        return Err("Insufficient balance".to_string());
    }

    BALANCES.with(|balances| {
        let mut balances = balances.borrow_mut();
        let new_balance = balance - amount.clone();
        if new_balance == Nat::from(0u64) {
            balances.remove(&from);
        } else {
            balances.insert(from, new_balance);
        }
    });

    TOTAL_SUPPLY.with(|supply| {
        let mut supply = supply.borrow_mut();
        *supply = supply.clone() - amount;
    });

    Ok(())
} 