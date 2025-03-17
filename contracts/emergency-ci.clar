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



;; Add at the top with other constants
(define-constant WITHDRAWAL-WINDOW u144) ;; ~24 hours in blocks
(define-map contribution-timestamps principal uint)

;; Add new function
(define-public (withdraw-contribution)
    (let ((user-contribution (get-contribution tx-sender))
          (contribution-time (default-to u0 (map-get? contribution-timestamps tx-sender))))
        (begin
            (asserts! (> user-contribution u0) ERR-INSUFFICIENT-FUNDS)
            (asserts! (< stacks-block-height (+ contribution-time WITHDRAWAL-WINDOW)) ERR-NOT-AUTHORIZED)
            (try! (as-contract (stx-transfer? user-contribution tx-sender tx-sender)))
            (var-set total-pool (- (var-get total-pool) user-contribution))
            (map-delete contributors tx-sender)
            (ok true))))




;; Add constants
(define-constant BRONZE-TIER u1000000)  ;; 1 STX
(define-constant SILVER-TIER u5000000)  ;; 5 STX
(define-constant GOLD-TIER u10000000)   ;; 10 STX

(define-map contributor-tiers principal (string-ascii 6))

(define-public (contribute-tier (tier (string-ascii 6)))
    (let ((amount (if (is-eq tier "bronze")
                     BRONZE-TIER
                     (if (is-eq tier "silver")
                         SILVER-TIER
                         (if (is-eq tier "gold")
                             GOLD-TIER
                             MINIMUM-CONTRIBUTION)))))
        (begin
            (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
            (map-set contributor-tiers tx-sender tier)
            (map-set contributors tx-sender (+ (default-to u0 (map-get? contributors tx-sender)) amount))
            (var-set total-pool (+ (var-get total-pool) amount))
            (ok true))))



;; Add with other variables
(define-data-var reserve-fund uint u0)
(define-constant RESERVE-RATIO u10) ;; 10% of contributions

(define-public (add-to-reserve)
    (let ((reserve-amount (/ (var-get total-pool) RESERVE-RATIO)))
        (begin
            (var-set reserve-fund (+ (var-get reserve-fund) reserve-amount))
            (var-set total-pool (- (var-get total-pool) reserve-amount))
            (ok true))))


(define-map claim-votes { claim-id: uint, voter: principal } bool)
(define-data-var claim-id-nonce uint u0)

(define-public (submit-claim-vote (claim-id uint) (approve bool))
    (begin
        (asserts! (> (get-contribution tx-sender) u0) ERR-NOT-AUTHORIZED)
        (map-set claim-votes {claim-id: claim-id, voter: tx-sender} approve)
        (ok true)))


(define-map referrals { referred: principal } { referrer: principal })
(define-constant REFERRAL-BONUS u50000) ;; 0.05 STX

(define-public (contribute-with-referral (referrer principal))
    (let ((amount MINIMUM-CONTRIBUTION))
        (begin
            (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
            (map-set referrals {referred: tx-sender} {referrer: referrer})
            (try! (as-contract (stx-transfer? REFERRAL-BONUS tx-sender referrer)))
            (map-set contributors tx-sender (+ (default-to u0 (map-get? contributors tx-sender)) amount))
            (var-set total-pool (+ (var-get total-pool) (- amount REFERRAL-BONUS)))
            (ok true))))



(define-constant MILESTONE-AMOUNT u100000000) ;; 100 STX
(define-map milestone-reached principal bool)

(define-public (check-milestone)
    (let ((user-contribution (get-contribution tx-sender)))
        (begin
            (asserts! (>= user-contribution MILESTONE-AMOUNT) ERR-NOT-AUTHORIZED)
            (asserts! (not (default-to false (map-get? milestone-reached tx-sender))) ERR-ALREADY-CLAIMED)
            (map-set milestone-reached tx-sender true)
            (try! (as-contract (stx-transfer? REFERRAL-BONUS tx-sender tx-sender)))
            (ok true))))



(define-map emergency-contacts principal (list 3 principal))

(define-public (set-emergency-contacts (contacts (list 3 principal)))
    (begin
        (map-set emergency-contacts tx-sender contacts)
        (ok true)))

(define-read-only (get-emergency-contacts (user principal))
    (map-get? emergency-contacts user))
