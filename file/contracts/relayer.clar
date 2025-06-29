;; =============================================================================
;; Gas Sponsored Relayer Contract - Phase 2
;; Enhanced with bug fixes, security improvements, and new functionality
;; =============================================================================

;; Error constants
(define-constant ERR-INVALID-NONCE (err u100))
(define-constant ERR-SIGNATURE-FAILED (err u101))
(define-constant ERR-TX-NOT-FOUND (err u102))
(define-constant ERR-UNAUTHORIZED (err u103))
(define-constant ERR-ALREADY-PAID (err u104))
(define-constant ERR-INSUFFICIENT-BALANCE (err u105))
(define-constant ERR-INVALID-AMOUNT (err u106))
(define-constant ERR-SPONSOR-NOT-FOUND (err u107))

;; Contract constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MIN-SPONSOR-DEPOSIT u1000000) ;; 1 STX minimum

;; Data structures
(define-map sponsored-tx 
  { tx-id: (buff 32) }
  {
    user: principal,
    sponsor: principal,
    contract-called: (string-ascii 128),
    function-called: (string-ascii 128),
    amount: uint,
    paid: bool,
    timestamp: uint,
    expiry: uint
  }
)

(define-map nonces principal uint)

;; Sponsor balance tracking for security
(define-map sponsor-balances principal uint)

;; Whitelist of allowed contracts for security
(define-map allowed-contracts (string-ascii 128) bool)

;; Events for better tracking
(define-map transaction-events 
  { event-id: uint }
  {
    event-type: (string-ascii 32),
    tx-id: (buff 32),
    user: principal,
    sponsor: principal,
    timestamp: uint
  }
)

(define-data-var event-counter uint u0)

;; =============================================================================
;; CORE FUNCTIONALITY
;; =============================================================================

(define-public (submit-sponsored-call
  (user principal)
  (contract-name (string-ascii 128))
  (function-name (string-ascii 128))
  (amount uint)
  (nonce uint)
  (expiry uint)
  (sig (buff 65))
)
  (let
    (
      (current-nonce (default-to u0 (map-get? nonces user)))
      (sponsor-balance (default-to u0 (map-get? sponsor-balances tx-sender)))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (begin
      ;; Validate inputs
      (asserts! (> amount u0) ERR-INVALID-AMOUNT)
      (asserts! (> expiry current-time) ERR-INVALID-NONCE)
      (asserts! (is-eq nonce (+ current-nonce u1)) ERR-INVALID-NONCE)
      (asserts! (>= sponsor-balance amount) ERR-INSUFFICIENT-BALANCE)
      
      ;; Check if contract is whitelisted (security enhancement)
      (asserts! (default-to false (map-get? allowed-contracts contract-name)) ERR-UNAUTHORIZED)
      
      ;; Construct preimage for signature verification (FIXED: proper concatenation)
      (let
        (
          (preimage (concat 
            (concat 
              (concat 
                (concat (unwrap-panic (to-consensus-buff? user)) (unwrap-panic (to-consensus-buff? nonce)))
                (unwrap-panic (to-consensus-buff? contract-name))
              )
              (unwrap-panic (to-consensus-buff? function-name))
            )
            (unwrap-panic (to-consensus-buff? amount))
          ))
          (tx-id (sha256 preimage))
        )
        
        ;; Verify signature (simplified approach)
        (if (secp256k1-verify (sha256 preimage) sig (hash160 (unwrap-panic (to-consensus-buff? user))))
          (begin
            ;; Store sponsored transaction
            (map-set sponsored-tx 
              { tx-id: tx-id }
              {
                user: user,
                sponsor: tx-sender,
                contract-called: contract-name,
                function-called: function-name,
                amount: amount,
                paid: false,
                timestamp: current-time,
                expiry: expiry
              }
            )
            
            ;; Update nonce
            (map-set nonces user nonce)
            
            ;; Reserve sponsor balance
            (map-set sponsor-balances tx-sender (- sponsor-balance amount))
            
            ;; Log event
            (log-transaction-event "SUBMITTED" tx-id user tx-sender)
            
            (ok tx-id)
          )
          ERR-SIGNATURE-FAILED
        )
      )
    )
  )
)

(define-public (mark-paid (tx-id (buff 32)))
  (let
    (
      ;; Check for empty/null tx-id
      (empty-tx-id 0x0000000000000000000000000000000000000000000000000000000000000000)
    )
    (begin
      ;; Validate tx-id is not empty
      (asserts! (not (is-eq tx-id empty-tx-id)) ERR-TX-NOT-FOUND)
      
      (match (map-get? sponsored-tx { tx-id: tx-id })
        some-tx
        (let
          (
            (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
            (sponsor (get sponsor some-tx))
          )
          (begin
            ;; Security: Only sponsor can mark as paid
            (asserts! (is-eq tx-sender sponsor) ERR-UNAUTHORIZED)
            (asserts! (not (get paid some-tx)) ERR-ALREADY-PAID)
            (asserts! (< current-time (get expiry some-tx)) ERR-INVALID-NONCE) ;; Check expiry
            
            ;; Mark as paid
            (map-set sponsored-tx 
              { tx-id: tx-id }
              (merge some-tx { paid: true })
            )
            
            ;; Log event
            (log-transaction-event "PAID" tx-id (get user some-tx) sponsor)
            
            (ok true)
          )
        )
        ERR-TX-NOT-FOUND
      )
    )
  )
)

;; NEW FUNCTIONALITY: Refund expired transactions
(define-public (refund-expired (tx-id (buff 32)))
  (let
    (
      ;; Check for empty/null tx-id
      (empty-tx-id 0x0000000000000000000000000000000000000000000000000000000000000000)
    )
    (begin
      ;; Validate tx-id is not empty
      (asserts! (not (is-eq tx-id empty-tx-id)) ERR-TX-NOT-FOUND)
      
      (match (map-get? sponsored-tx { tx-id: tx-id })
        some-tx
        (let
          (
            (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
            (sponsor (get sponsor some-tx))
            (amount (get amount some-tx))
            (current-balance (default-to u0 (map-get? sponsor-balances sponsor)))
          )
          (begin
            ;; Check if transaction has expired and not paid
            (asserts! (>= current-time (get expiry some-tx)) ERR-INVALID-NONCE)
            (asserts! (not (get paid some-tx)) ERR-ALREADY-PAID)
            
            ;; Refund sponsor balance
            (map-set sponsor-balances sponsor (+ current-balance amount))
            
            ;; Mark as paid to prevent double refund
            (map-set sponsored-tx 
              { tx-id: tx-id }
              (merge some-tx { paid: true })
            )
            
            ;; Log event
            (log-transaction-event "REFUNDED" tx-id (get user some-tx) sponsor)
            
            (ok true)
          )
        )
        ERR-TX-NOT-FOUND
      )
    )
  )
)

;; =============================================================================
;; SPONSOR MANAGEMENT
;; =============================================================================

(define-public (deposit-sponsor-balance (amount uint))
  (let
    (
      (current-balance (default-to u0 (map-get? sponsor-balances tx-sender)))
    )
    (begin
      (asserts! (>= amount MIN-SPONSOR-DEPOSIT) ERR-INVALID-AMOUNT)
      
      ;; Transfer STX to contract
      (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
      
      ;; Update sponsor balance
      (map-set sponsor-balances tx-sender (+ current-balance amount))
      
      (ok true)
    )
  )
)

(define-public (withdraw-sponsor-balance (amount uint))
  (let
    (
      (current-balance (default-to u0 (map-get? sponsor-balances tx-sender)))
    )
    (begin
      (asserts! (>= current-balance amount) ERR-INSUFFICIENT-BALANCE)
      
      ;; Update balance first (prevent reentrancy)
      (map-set sponsor-balances tx-sender (- current-balance amount))
      
      ;; Transfer STX back to sponsor
      (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
      
      (ok true)
    )
  )
)

;; =============================================================================
;; ADMIN FUNCTIONS (Security Enhancement)
;; =============================================================================

(define-public (add-allowed-contract (contract-name (string-ascii 128)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    ;; Validate contract name is not empty
    (asserts! (> (len contract-name) u0) ERR-INVALID-AMOUNT)
    (map-set allowed-contracts contract-name true)
    (ok true)
  )
)

(define-public (remove-allowed-contract (contract-name (string-ascii 128)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    ;; Validate contract name is not empty
    (asserts! (> (len contract-name) u0) ERR-INVALID-AMOUNT)
    (map-delete allowed-contracts contract-name)
    (ok true)
  )
)

;; =============================================================================
;; READ-ONLY FUNCTIONS
;; =============================================================================

(define-read-only (get-sponsored-info (tx-id (buff 32)))
  (map-get? sponsored-tx { tx-id: tx-id })
)

(define-read-only (get-user-nonce (user principal))
  (default-to u0 (map-get? nonces user))
)

(define-read-only (get-sponsor-balance (sponsor principal))
  (default-to u0 (map-get? sponsor-balances sponsor))
)

(define-read-only (is-contract-allowed (contract-name (string-ascii 128)))
  (default-to false (map-get? allowed-contracts contract-name))
)

(define-read-only (get-transaction-event (event-id uint))
  (map-get? transaction-events { event-id: event-id })
)

;; =============================================================================
;; HELPER FUNCTIONS
;; =============================================================================

(define-private (log-transaction-event 
  (event-type (string-ascii 32))
  (tx-id (buff 32))
  (user principal)
  (sponsor principal)
)
  (let
    (
      (event-id (+ (var-get event-counter) u1))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (begin
      (map-set transaction-events
        { event-id: event-id }
        {
          event-type: event-type,
          tx-id: tx-id,
          user: user,
          sponsor: sponsor,
          timestamp: current-time
        }
      )
      (var-set event-counter event-id)
      event-id
    )
  )
)
