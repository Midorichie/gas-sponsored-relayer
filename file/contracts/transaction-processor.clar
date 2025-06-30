;; =============================================================================
;; Transaction Processor Contract
;; Handles execution of sponsored transactions with fee management integration
;; =============================================================================

;; Error constants
(define-constant ERR-UNAUTHORIZED (err u300))
(define-constant ERR-INVALID-SIGNATURE (err u301))
(define-constant ERR-EXPIRED-TRANSACTION (err u302))
(define-constant ERR-INSUFFICIENT-BALANCE (err u303))
(define-constant ERR-TRANSACTION-FAILED (err u304))
(define-constant ERR-INVALID-CONTRACT (err u305))
(define-constant ERR-ALREADY-PROCESSED (err u306))
(define-constant ERR-INVALID-PARAMETERS (err u307))
(define-constant ERR-FEE-CALCULATION-FAILED (err u308))

;; Contract constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MAX-BATCH-SIZE u50)

;; Contract references (set by admin)
(define-data-var relayer-contract (optional principal) none)
(define-data-var fee-manager-contract (optional principal) none)

;; Transaction execution tracking
(define-map processed-transactions
  { tx-hash: (buff 32) }
  {
    user: principal,
    sponsor: principal,
    contract-called: (string-ascii 128),
    function-called: (string-ascii 128),
    amount: uint,
    fee-paid: uint,
    status: (string-ascii 16), ;; "SUCCESS", "FAILED", "PENDING"
    processed-at: uint,
    gas-used: uint
  }
)

;; Batch processing tracking
(define-map batch-executions
  { batch-id: uint }
  {
    sponsor: principal,
    transaction-count: uint,
    total-fees: uint,
    executed-at: uint,
    success-count: uint,
    failed-count: uint
  }
)

(define-data-var batch-counter uint u0)
(define-data-var total-transactions-processed uint u0)

;; Supported contract calls (whitelist)
(define-map supported-contracts
  { contract-address: principal }
  {
    contract-name: (string-ascii 128),
    allowed-functions: (list 20 (string-ascii 64)),
    active: bool,
    added-at: uint
  }
)

;; =============================================================================
;; ADMIN FUNCTIONS
;; =============================================================================

(define-public (set-relayer-contract (contract-address principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (var-set relayer-contract (some contract-address))
    (ok true)
  )
)

(define-public (set-fee-manager-contract (contract-address principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (var-set fee-manager-contract (some contract-address))
    (ok true)
  )
)

(define-public (add-supported-contract 
  (contract-address principal)
  (contract-name (string-ascii 128))
  (allowed-functions (list 20 (string-ascii 64)))
)
  (let
    (
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (begin
      (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
      (asserts! (> (len contract-name) u0) ERR-INVALID-PARAMETERS)
      (asserts! (> (len allowed-functions) u0) ERR-INVALID-PARAMETERS)
      
      (map-set supported-contracts
        { contract-address: contract-address }
        {
          contract-name: contract-name,
          allowed-functions: allowed-functions,
          active: true,
          added-at: current-time
        }
      )
      
      (ok true)
    )
  )
)

(define-public (toggle-contract-support (contract-address principal) (active bool))
  (match (map-get? supported-contracts { contract-address: contract-address })
    some-contract
    (begin
      (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
      (map-set supported-contracts
        { contract-address: contract-address }
        (merge some-contract { active: active })
      )
      (ok true)
    )
    ERR-INVALID-CONTRACT
  )
)

;; =============================================================================
;; TRANSACTION PROCESSING
;; =============================================================================

(define-public (process-sponsored-transaction
  (tx-hash (buff 32))
  (user principal)
  (contract-address principal)
  (function-name (string-ascii 64))
  (amount uint)
  (parameters (list 10 (buff 256)))
)
  (let
    (
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
      (relayer-contract-addr (var-get relayer-contract))
    )
    ;; Early validation checks
    (if (is-none relayer-contract-addr)
      (err ERR-INVALID-CONTRACT)
      (if (not (is-eq contract-caller (unwrap-panic relayer-contract-addr)))
        (err ERR-UNAUTHORIZED)
        (if (is-some (map-get? processed-transactions { tx-hash: tx-hash }))
          (err ERR-ALREADY-PROCESSED)
          (if (not (is-contract-function-supported contract-address function-name))
            (err ERR-INVALID-CONTRACT)
            ;; All validations passed, proceed with transaction processing
            (let
              (
                (contract-info-opt (map-get? supported-contracts { contract-address: contract-address }))
              )
              (if (is-none contract-info-opt)
                (err ERR-INVALID-CONTRACT)
                (let
                  (
                    (contract-info (unwrap-panic contract-info-opt))
                    (contract-name (get contract-name contract-info))
                    (calculated-fee (calculate-simple-fee amount))
                  )
                  (begin
                    ;; Record transaction as pending
                    (map-set processed-transactions
                      { tx-hash: tx-hash }
                      {
                        user: user,
                        sponsor: tx-sender,
                        contract-called: contract-name,
                        function-called: function-name,
                        amount: amount,
                        fee-paid: calculated-fee,
                        status: "PENDING",
                        processed-at: current-time,
                        gas-used: u0
                      }
                    )
                    
                    ;; Execute the actual transaction
                    (let ((execution-result (execute-contract-call contract-address function-name amount parameters)))
                      (if (is-ok execution-result)
                        (let ((gas-used (unwrap-panic execution-result)))
                          (begin
                            ;; Update status to success
                            (map-set processed-transactions
                              { tx-hash: tx-hash }
                              (merge 
                                (unwrap-panic (map-get? processed-transactions { tx-hash: tx-hash }))
                                { status: "SUCCESS", gas-used: gas-used }
                              )
                            )
                            
                            ;; Update counters
                            (var-set total-transactions-processed (+ (var-get total-transactions-processed) u1))
                            
                            (ok { fee-paid: calculated-fee, gas-used: gas-used })
                          )
                        )
                        ;; Transaction failed
                        (begin
                          ;; Update status to failed
                          (map-set processed-transactions
                            { tx-hash: tx-hash }
                            (merge 
                              (unwrap-panic (map-get? processed-transactions { tx-hash: tx-hash }))
                              { status: "FAILED" }
                            )
                          )
                          
                          (err ERR-TRANSACTION-FAILED)
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  )
)

(define-public (process-batch-transactions
  (transactions (list 50 {
    tx-hash: (buff 32),
    user: principal,
    contract-address: principal,
    function-name: (string-ascii 64),
    amount: uint,
    parameters: (list 10 (buff 256))
  }))
)
  (let
    (
      (batch-id (+ (var-get batch-counter) u1))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
      (total-count (len transactions))
    )
    (if (<= total-count MAX-BATCH-SIZE)
      (let
        (
          (batch-result (process-transactions-batch transactions u0 u0 u0))
          (success-count (get success-count batch-result))
          (total-fees (get total-fees batch-result))
        )
        (begin
          ;; Record batch execution
          (map-set batch-executions
            { batch-id: batch-id }
            {
              sponsor: tx-sender,
              transaction-count: total-count,
              total-fees: total-fees,
              executed-at: current-time,
              success-count: success-count,
              failed-count: (- total-count success-count)
            }
          )
          
          ;; Update batch counter
          (var-set batch-counter batch-id)
          
          (ok {
            batch-id: batch-id,
            processed: total-count,
            successful: success-count,
            failed: (- total-count success-count)
          })
        )
      )
      (err ERR-INVALID-PARAMETERS)
    )
  )
)

;; =============================================================================
;; HELPER FUNCTIONS
;; =============================================================================

(define-private (calculate-simple-fee (amount uint))
  ;; Simple fee calculation: 1% of amount, minimum 1000 micro-STX
  (let
    (
      (percentage-fee (/ amount u100))
      (minimum-fee u1000)
    )
    (if (> percentage-fee minimum-fee) percentage-fee minimum-fee)
  )
)

(define-private (execute-contract-call
  (contract-address principal)
  (function-name (string-ascii 64))
  (amount uint)
  (parameters (list 10 (buff 256)))
)
  ;; Simplified execution - in practice, this would use dynamic contract calls
  ;; For now, return a mock gas usage based on amount
  ;; Using explicit ok/err to make the return type clear
  (if (> amount u0)
    (ok (+ u1000 (/ amount u1000)))
    (err ERR-INVALID-PARAMETERS)
  )
)

(define-private (process-single-transaction (tx-data {
  tx-hash: (buff 32),
  user: principal,
  contract-address: principal,
  function-name: (string-ascii 64),
  amount: uint,
  parameters: (list 10 (buff 256))
}))
  (process-sponsored-transaction
    (get tx-hash tx-data)
    (get user tx-data)
    (get contract-address tx-data)
    (get function-name tx-data)
    (get amount tx-data)
    (get parameters tx-data)
  )
)

(define-private (process-transactions-batch 
  (transactions (list 50 {
    tx-hash: (buff 32),
    user: principal,
    contract-address: principal,
    function-name: (string-ascii 64),
    amount: uint,
    parameters: (list 10 (buff 256))
  }))
  (success-count uint)
  (total-fees uint)
  (index uint)
)
  (fold process-transaction-in-batch transactions { success-count: u0, total-fees: u0 })
)

(define-private (process-transaction-in-batch 
  (tx-data {
    tx-hash: (buff 32),
    user: principal,
    contract-address: principal,
    function-name: (string-ascii 64),
    amount: uint,
    parameters: (list 10 (buff 256))
  })
  (acc { success-count: uint, total-fees: uint })
)
  (let
    (
      (result (process-sponsored-transaction
        (get tx-hash tx-data)
        (get user tx-data)
        (get contract-address tx-data)
        (get function-name tx-data)
        (get amount tx-data)
        (get parameters tx-data)
      ))
    )
    (if (is-ok result)
      (let ((ok-val (unwrap-panic result)))
        {
          success-count: (+ (get success-count acc) u1),
          total-fees: (+ (get total-fees acc) (get fee-paid ok-val))
        }
      )
      acc
    )
  )
)

(define-private (process-results-for-count 
  (results (list 50 (response { fee-paid: uint, gas-used: uint } uint)))
)
  (fold count-if-ok results u0)
)

(define-private (process-results-for-fees 
  (results (list 50 (response { fee-paid: uint, gas-used: uint } uint)))
)
  (fold sum-fees results u0)
)

(define-private (count-if-ok 
  (result (response { fee-paid: uint, gas-used: uint } uint))
  (acc uint)
)
  (if (is-ok result) (+ acc u1) acc)
)

(define-private (sum-fees 
  (result (response { fee-paid: uint, gas-used: uint } uint))
  (acc uint)
)
  (match result
    ok-val (+ acc (get fee-paid ok-val))
    err-val acc
  )
)

(define-read-only (is-contract-function-supported (contract-address principal) (function-name (string-ascii 64)))
  (match (map-get? supported-contracts { contract-address: contract-address })
    some-contract
    (and 
      (get active some-contract)
      (is-some (index-of (get allowed-functions some-contract) function-name))
    )
    false
  )
)

;; =============================================================================
;; READ-ONLY FUNCTIONS
;; =============================================================================

(define-read-only (get-transaction-status (tx-hash (buff 32)))
  (map-get? processed-transactions { tx-hash: tx-hash })
)

(define-read-only (get-batch-info (batch-id uint))
  (map-get? batch-executions { batch-id: batch-id })
)

(define-read-only (get-supported-contract (contract-address principal))
  (map-get? supported-contracts { contract-address: contract-address })
)

(define-read-only (get-processing-stats)
  {
    total-processed: (var-get total-transactions-processed),
    total-batches: (var-get batch-counter),
    relayer-contract: (var-get relayer-contract),
    fee-manager-contract: (var-get fee-manager-contract)
  }
)

(define-read-only (get-contract-references)
  {
    relayer: (var-get relayer-contract),
    fee-manager: (var-get fee-manager-contract)
  }
)

;; =============================================================================
;; VALIDATION FUNCTIONS
;; =============================================================================

(define-read-only (validate-transaction-parameters
  (user principal)
  (contract-address principal)
  (function-name (string-ascii 64))
  (amount uint)
)
  (and
    (> amount u0)
    (> (len function-name) u0)
    (is-contract-function-supported contract-address function-name)
  )
)
