;; Emergency Crowdfunding Insurance

;; Constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INSUFFICIENT-FUNDS (err u101))
(define-constant ERR-ALREADY-CLAIMED (err u102))
(define-constant MINIMUM-CONTRIBUTION u1000000) ;; 1 STX

;; Data Maps
(define-map contributors principal uint)
(define-map claims { beneficiary: principal } { claimed: bool, amount: uint })
(define-data-var total-pool uint u0)
(define-data-var contract-owner principal tx-sender)

;; Public Functions
(define-public (contribute)
    (let ((amount MINIMUM-CONTRIBUTION))
        (begin
            (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
            (map-set contributors tx-sender (+ (default-to u0 (map-get? contributors tx-sender)) amount))
            (var-set total-pool (+ (var-get total-pool) amount))
            (ok true))))

(define-public (create-claim (amount uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (>= (var-get total-pool) amount) ERR-INSUFFICIENT-FUNDS)
        (map-set claims {beneficiary: tx-sender} {claimed: false, amount: amount})
        (ok true)))

;; Update the claim-payout function to allow beneficiary claims
(define-public (claim-payout (beneficiary principal))
    (let ((claim-data (unwrap! (map-get? claims {beneficiary: beneficiary}) ERR-NOT-AUTHORIZED)))
        (begin
            (asserts! (is-eq tx-sender beneficiary) ERR-NOT-AUTHORIZED)
            (asserts! (not (get claimed claim-data)) ERR-ALREADY-CLAIMED)
            (asserts! (>= (var-get total-pool) (get amount claim-data)) ERR-INSUFFICIENT-FUNDS)
            (try! (as-contract (stx-transfer? (get amount claim-data) tx-sender beneficiary)))
            (var-set total-pool (- (var-get total-pool) (get amount claim-data)))
            (map-set claims {beneficiary: beneficiary} (merge claim-data {claimed: true}))
            (ok true))))


;; Read Only Functions
(define-read-only (get-pool-balance)
    (var-get total-pool))

(define-read-only (get-contribution (contributor principal))
    (default-to u0 (map-get? contributors contributor)))

(define-read-only (get-claim (beneficiary principal))
    (map-get? claims {beneficiary: beneficiary}))
