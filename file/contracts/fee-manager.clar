;; =============================================================================
;; Fee Manager Contract
;; Manages dynamic fee structures for the gas sponsored relayer
;; =============================================================================

;; Error constants
(define-constant ERR-UNAUTHORIZED (err u200))
(define-constant ERR-INVALID-FEE (err u201))
(define-constant ERR-CONTRACT-NOT-FOUND (err u202))
(define-constant ERR-INVALID-PERCENTAGE (err u203))

;; Contract constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MAX-FEE-PERCENTAGE u1000) ;; 10% max fee (basis points)
(define-constant MIN-FEE u100) ;; Minimum fee in microSTX

;; Fee structure for different contracts
(define-map contract-fees 
  { contract-name: (string-ascii 128) }
  {
    base-fee: uint,
    percentage-fee: uint, ;; In basis points (100 = 1%)
    max-fee: uint,
    active: bool,
    updated-at: uint
  }
)

;; Global fee settings
(define-map global-settings 
  { setting-name: (string-ascii 32) }
  { value: uint }
)

;; Fee collection tracking
(define-map fee-collections
  { collection-id: uint }
  {
    contract-name: (string-ascii 128),
    fee-amount: uint,
    transaction-amount: uint,
    collected-at: uint,
    sponsor: principal
  }
)

(define-data-var collection-counter uint u0)
(define-data-var total-fees-collected uint u0)

;; =============================================================================
;; ADMIN FUNCTIONS
;; =============================================================================

(define-public (set-contract-fee
  (contract-name (string-ascii 128))
  (base-fee uint)
  (percentage-fee uint)
  (max-fee uint)
)
  (let
    (
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (begin
      (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
      (asserts! (>= base-fee MIN-FEE) ERR-INVALID-FEE)
      (asserts! (<= percentage-fee MAX-FEE-PERCENTAGE) ERR-INVALID-PERCENTAGE)
      (asserts! (>= max-fee base-fee) ERR-INVALID-FEE)
      
      (map-set contract-fees
        { contract-name: contract-name }
        {
          base-fee: base-fee,
          percentage-fee: percentage-fee,
          max-fee: max-fee,
          active: true,
          updated-at: current-time
        }
      )
      
      (ok true)
    )
  )
)

(define-public (toggle-contract-fee (contract-name (string-ascii 128)) (active bool))
  (match (map-get? contract-fees { contract-name: contract-name })
    some-fee
    (begin
      (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
      (map-set contract-fees
        { contract-name: contract-name }
        (merge some-fee { active: active })
      )
      (ok true)
    )
    ERR-CONTRACT-NOT-FOUND
  )
)

(define-public (set-global-setting (setting-name (string-ascii 32)) (value uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (map-set global-settings { setting-name: setting-name } { value: value })
    (ok true)
  )
)

;; =============================================================================
;; FEE CALCULATION AND COLLECTION
;; =============================================================================

(define-read-only (calculate-fee (contract-name (string-ascii 128)) (transaction-amount uint))
  (match (map-get? contract-fees { contract-name: contract-name })
    some-fee
    (if (get active some-fee)
      (let
        (
          (base-fee (get base-fee some-fee))
          (percentage-fee (get percentage-fee some-fee))
          (max-fee (get max-fee some-fee))
          (calculated-percentage (/ (* transaction-amount percentage-fee) u10000))
          (total-fee (+ base-fee calculated-percentage))
          (final-fee (if (> total-fee max-fee) max-fee total-fee))
        )
        (ok final-fee)
      )
      (ok u0) ;; No fee if not active
    )
    (ok u0) ;; Default to no fee if contract not configured
  )
)

(define-public (collect-fee 
  (contract-name (string-ascii 128))
  (transaction-amount uint)
  (sponsor principal)
)
  (let
    (
      (collection-id (+ (var-get collection-counter) u1))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
      (fee-amount (unwrap-panic (calculate-fee contract-name transaction-amount)))
    )
    (begin
      ;; Only collect if there's a fee
      (if (> fee-amount u0)
        (begin
          ;; Record fee collection
          (map-set fee-collections
            { collection-id: collection-id }
            {
              contract-name: contract-name,
              fee-amount: fee-amount,
              transaction-amount: transaction-amount,
              collected-at: current-time,
              sponsor: sponsor
            }
          )
          
          ;; Update counters
          (var-set collection-counter collection-id)
          (var-set total-fees-collected (+ (var-get total-fees-collected) fee-amount))
          
          (ok fee-amount)
        )
        (ok u0)
      )
    )
  )
)

;; =============================================================================
;; READ-ONLY FUNCTIONS
;; =============================================================================

(define-read-only (get-contract-fee (contract-name (string-ascii 128)))
  (map-get? contract-fees { contract-name: contract-name })
)

(define-read-only (get-global-setting (setting-name (string-ascii 32)))
  (map-get? global-settings { setting-name: setting-name })
)

(define-read-only (get-fee-collection (collection-id uint))
  (map-get? fee-collections { collection-id: collection-id })
)

(define-read-only (get-total-fees-collected)
  (var-get total-fees-collected)
)

(define-read-only (get-collection-count)
  (var-get collection-counter)
)

;; Calculate fee without storing (for preview)
(define-read-only (preview-fee (contract-name (string-ascii 128)) (transaction-amount uint))
  (match (map-get? contract-fees { contract-name: contract-name })
    some-fee
    (if (get active some-fee)
      (let
        (
          (base-fee (get base-fee some-fee))
          (percentage-fee (get percentage-fee some-fee))
          (max-fee (get max-fee some-fee))
          (calculated-percentage (/ (* transaction-amount percentage-fee) u10000))
          (total-fee (+ base-fee calculated-percentage))
        )
        (if (> total-fee max-fee) max-fee total-fee)
      )
      u0
    )
    u0
  )
)

;; =============================================================================
;; ANALYTICS FUNCTIONS
;; =============================================================================

(define-read-only (get-contract-stats (contract-name (string-ascii 128)))
  (let
    (
      (fee-config (map-get? contract-fees { contract-name: contract-name }))
    )
    {
      fee-config: fee-config,
      total-collections: (var-get collection-counter),
      total-fees: (var-get total-fees-collected)
    }
  )
)
