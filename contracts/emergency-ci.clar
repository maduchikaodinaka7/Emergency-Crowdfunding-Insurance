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


;; Add these constants and maps
(define-constant CAMPAIGN-ACTIVE u1)
(define-constant CAMPAIGN-ENDED u2)
(define-map emergency-campaigns 
  { campaign-id: uint } 
  { 
    name: (string-ascii 50), 
    description: (string-ascii 100),
    target-amount: uint, 
    current-amount: uint,
    end-block: uint,
    status: uint
  }
)
(define-map campaign-contributions 
  { campaign-id: uint, contributor: principal } 
  uint
)
(define-data-var campaign-id-counter uint u0)

;; Create a new emergency campaign
(define-public (create-emergency-campaign 
    (name (string-ascii 50)) 
    (description (string-ascii 100))
    (target-amount uint)
    (duration uint))
  (let ((campaign-id (var-get campaign-id-counter))
        (end-block (+ stacks-block-height duration)))
    (begin
      (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
      (map-set emergency-campaigns 
        { campaign-id: campaign-id }
        { 
          name: name, 
          description: description,
          target-amount: target-amount, 
          current-amount: u0,
          end-block: end-block,
          status: CAMPAIGN-ACTIVE
        }
      )
      (var-set campaign-id-counter (+ campaign-id u1))
      (ok campaign-id))))

;; Contribute to a specific campaign
(define-public (contribute-to-campaign (campaign-id uint) (amount uint))
  (let ((campaign (unwrap! (map-get? emergency-campaigns { campaign-id: campaign-id }) (err u103)))
        (current-contribution (default-to u0 (map-get? campaign-contributions { campaign-id: campaign-id, contributor: tx-sender }))))
    (begin
      (asserts! (is-eq (get status campaign) CAMPAIGN-ACTIVE) (err u104))
      (asserts! (<= stacks-block-height (get end-block campaign)) (err u105))
      (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
      (map-set campaign-contributions 
        { campaign-id: campaign-id, contributor: tx-sender }
        (+ current-contribution amount))
      (map-set emergency-campaigns
        { campaign-id: campaign-id }
        (merge campaign { current-amount: (+ (get current-amount campaign) amount) }))
      (var-set total-pool (+ (var-get total-pool) amount))
      (ok true))))

;; End a campaign
(define-public (end-campaign (campaign-id uint))
  (let ((campaign (unwrap! (map-get? emergency-campaigns { campaign-id: campaign-id }) (err u103))))
    (begin
      (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
      (asserts! (is-eq (get status campaign) CAMPAIGN-ACTIVE) (err u104))
      (map-set emergency-campaigns
        { campaign-id: campaign-id }
        (merge campaign { status: CAMPAIGN-ENDED }))
      (ok true))))

;; Get campaign details
(define-read-only (get-campaign-details (campaign-id uint))
  (map-get? emergency-campaigns { campaign-id: campaign-id }))

;; Get user contribution to a campaign
(define-read-only (get-campaign-contribution (campaign-id uint) (contributor principal))
  (default-to u0 (map-get? campaign-contributions { campaign-id: campaign-id, contributor: contributor })))





;; Add these constants and maps
(define-constant PROPOSAL-ACTIVE u1)
(define-constant PROPOSAL-PASSED u2)
(define-constant PROPOSAL-REJECTED u3)
(define-constant PROPOSAL-EXECUTED u4)

(define-map governance-proposals
  { proposal-id: uint }
  {
    title: (string-ascii 50),
    description: (string-ascii 200),
    beneficiary: principal,
    amount: uint,
    votes-for: uint,
    votes-against: uint,
    status: uint,
    end-block: uint
  }
)

(define-map proposal-votes
  { proposal-id: uint, voter: principal }
  bool
)

(define-data-var proposal-id-counter uint u0)

;; Create a governance proposal
(define-public (create-proposal 
    (title (string-ascii 50)) 
    (description (string-ascii 200))
    (beneficiary principal)
    (amount uint)
    (voting-period uint))
  (let ((proposal-id (var-get proposal-id-counter))
        (end-block (+ stacks-block-height voting-period)))
    (begin
      (asserts! (>= (get-contribution tx-sender) MINIMUM-CONTRIBUTION) ERR-NOT-AUTHORIZED)
      (map-set governance-proposals
        { proposal-id: proposal-id }
        {
          title: title,
          description: description,
          beneficiary: beneficiary,
          amount: amount,
          votes-for: u0,
          votes-against: u0,
          status: PROPOSAL-ACTIVE,
          end-block: end-block
        }
      )
      (var-set proposal-id-counter (+ proposal-id u1))
      (ok proposal-id))))

;; Vote on a proposal
(define-public (vote-on-proposal (proposal-id uint) (vote-for bool))
  (let ((proposal (unwrap! (map-get? governance-proposals { proposal-id: proposal-id }) (err u106)))
        (user-contribution (get-contribution tx-sender))
        (has-voted (is-some (map-get? proposal-votes { proposal-id: proposal-id, voter: tx-sender }))))
    (begin
      (asserts! (> user-contribution u0) ERR-NOT-AUTHORIZED)
      (asserts! (is-eq (get status proposal) PROPOSAL-ACTIVE) (err u107))
      (asserts! (<= stacks-block-height (get end-block proposal)) (err u108))
      (asserts! (not has-voted) (err u109))
      
      (map-set proposal-votes { proposal-id: proposal-id, voter: tx-sender } vote-for)
      
      (map-set governance-proposals
        { proposal-id: proposal-id }
        (merge proposal 
          {
            votes-for: (if vote-for (+ (get votes-for proposal) user-contribution) (get votes-for proposal)),
            votes-against: (if vote-for (get votes-against proposal) (+ (get votes-against proposal) user-contribution))
          }
        ))
      (ok true))))

;; Finalize a proposal
(define-public (finalize-proposal (proposal-id uint))
  (let ((proposal (unwrap! (map-get? governance-proposals { proposal-id: proposal-id }) (err u106))))
    (begin
      (asserts! (is-eq (get status proposal) PROPOSAL-ACTIVE) (err u107))
      (asserts! (>= stacks-block-height (get end-block proposal)) (err u108))
      
      (if (> (get votes-for proposal) (get votes-against proposal))
        (map-set governance-proposals
          { proposal-id: proposal-id }
          (merge proposal { status: PROPOSAL-PASSED }))
        (map-set governance-proposals
          { proposal-id: proposal-id }
          (merge proposal { status: PROPOSAL-REJECTED })))
      (ok true))))

;; Execute a passed proposal
(define-public (execute-proposal (proposal-id uint))
  (let ((proposal (unwrap! (map-get? governance-proposals { proposal-id: proposal-id }) (err u106))))
    (begin
      (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
      (asserts! (is-eq (get status proposal) PROPOSAL-PASSED) (err u110))
      (asserts! (>= (var-get total-pool) (get amount proposal)) ERR-INSUFFICIENT-FUNDS)
      
      (try! (as-contract (stx-transfer? (get amount proposal) tx-sender (get beneficiary proposal))))
      (var-set total-pool (- (var-get total-pool) (get amount proposal)))
      
      (map-set governance-proposals
        { proposal-id: proposal-id }
        (merge proposal { status: PROPOSAL-EXECUTED }))
      (ok true))))

;; Get proposal details
(define-read-only (get-proposal-details (proposal-id uint))
  (map-get? governance-proposals { proposal-id: proposal-id }))



;; Add these constants and maps
(define-constant REWARD-BRONZE u1)
(define-constant REWARD-SILVER u2)
(define-constant REWARD-GOLD u3)
(define-constant REWARD-PLATINUM u4)

(define-map user-rewards principal uint)
(define-map reward-claimed { user: principal, reward-level: uint } bool)

;; Calculate and update user reward tier
(define-public (update-reward-tier)
  (let ((user-contribution (get-contribution tx-sender))
        (current-tier (default-to u0 (map-get? user-rewards tx-sender))))
    (begin
      (asserts! (> user-contribution u0) ERR-NOT-AUTHORIZED)
      
      (map-set user-rewards tx-sender 
        (if (>= user-contribution u50000000) 
            REWARD-PLATINUM
            (if (>= user-contribution u20000000)
                REWARD-GOLD
                (if (>= user-contribution u10000000)
                    REWARD-SILVER
                    (if (>= user-contribution u5000000)
                        REWARD-BRONZE
                        u0)))))
      (ok true))))

;; Claim reward based on tier
(define-public (claim-tier-reward)
  (let ((user-tier (default-to u0 (map-get? user-rewards tx-sender)))
        (already-claimed (default-to false (map-get? reward-claimed { user: tx-sender, reward-level: user-tier }))))
    (begin
      (asserts! (> user-tier u0) (err u111))
      (asserts! (not already-claimed) (err u112))
      
      ;; Set reward amount based on tier
      (let ((reward-amount 
        (if (is-eq user-tier REWARD-PLATINUM) 
            u1000000  ;; 1 STX
            (if (is-eq user-tier REWARD-GOLD)
                u500000  ;; 0.5 STX
                (if (is-eq user-tier REWARD-SILVER)
                    u200000  ;; 0.2 STX
                    (if (is-eq user-tier REWARD-BRONZE)
                        u100000  ;; 0.1 STX
                        u0))))))
        
        (try! (as-contract (stx-transfer? reward-amount tx-sender tx-sender)))
        (map-set reward-claimed { user: tx-sender, reward-level: user-tier } true)
        (ok reward-amount)))))

;; Get user reward tier
(define-read-only (get-user-reward-tier (user principal))
  (default-to u0 (map-get? user-rewards user)))

;; Check if reward has been claimed
(define-read-only (is-reward-claimed (user principal) (reward-level uint))
  (default-to false (map-get? reward-claimed { user: user, reward-level: reward-level })))
;; Add these constants and maps
(define-constant VERIFICATION-PENDING u1)
(define-constant VERIFICATION-APPROVED u2)
(define-constant VERIFICATION-REJECTED u3)

(define-map disaster-verifications
  { disaster-id: uint }
  {
    location: (string-ascii 50),
    disaster-type: (string-ascii 30),
    timestamp: uint,
    verification-status: uint,
    oracle-address: principal
  }
)

(define-map authorized-oracles principal bool)
(define-data-var disaster-id-counter uint u0)

;; Add an authorized oracle
(define-public (add-oracle (oracle-address principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (map-set authorized-oracles oracle-address true)
    (ok true)))

;; Remove an oracle
(define-public (remove-oracle (oracle-address principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (map-delete authorized-oracles oracle-address)
    (ok true)))

;; Register a disaster for verification
(define-public (register-disaster 
    (location (string-ascii 50))
    (disaster-type (string-ascii 30))
    (oracle-address principal))
  (let ((disaster-id (var-get disaster-id-counter)))
    (begin
      (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
      (asserts! (default-to false (map-get? authorized-oracles oracle-address)) (err u113))
      
      (map-set disaster-verifications
        { disaster-id: disaster-id }
        {
          location: location,
          disaster-type: disaster-type,
          timestamp: stacks-block-height,
          verification-status: VERIFICATION-PENDING,
          oracle-address: oracle-address
        }
      )
      (var-set disaster-id-counter (+ disaster-id u1))
      (ok disaster-id))))

;; Oracle verifies a disaster
(define-public (verify-disaster (disaster-id uint) (approve bool))
  (let ((disaster (unwrap! (map-get? disaster-verifications { disaster-id: disaster-id }) (err u114))))
    (begin
      (asserts! (is-eq tx-sender (get oracle-address disaster)) ERR-NOT-AUTHORIZED)
      (asserts! (is-eq (get verification-status disaster) VERIFICATION-PENDING) (err u115))
      
      (map-set disaster-verifications
        { disaster-id: disaster-id }
        (merge disaster 
          { verification-status: (if approve VERIFICATION-APPROVED VERIFICATION-REJECTED) }
        ))
      (ok true))))

;; Get disaster verification details
(define-read-only (get-disaster-verification (disaster-id uint))
  (map-get? disaster-verifications { disaster-id: disaster-id }))

;; Check if an address is an authorized oracle
(define-read-only (is-authorized-oracle (address principal))
  (default-to false (map-get? authorized-oracles address)))



(define-constant TIMELOCK-ACTIVE u1)
(define-constant TIMELOCK-EXPIRED u2)

(define-map timelocked-pools 
  { pool-id: uint }
  {
    name: (string-ascii 50),
    lock-duration: uint,
    start-block: uint,
    total-locked: uint,
    status: uint
  }
)

(define-map pool-deposits
  { pool-id: uint, depositor: principal }
  uint
)

(define-data-var pool-id-counter uint u0)

(define-public (create-timelock-pool (name (string-ascii 50)) (lock-duration uint))
  (let ((pool-id (var-get pool-id-counter)))
    (begin
      (map-set timelocked-pools
        { pool-id: pool-id }
        {
          name: name,
          lock-duration: lock-duration,
          start-block: stacks-block-height,
          total-locked: u0,
          status: TIMELOCK-ACTIVE
        }
      )
      (var-set pool-id-counter (+ pool-id u1))
      (ok pool-id))))

(define-public (deposit-to-timelock (pool-id uint) (amount uint))
  (let ((pool (unwrap! (map-get? timelocked-pools { pool-id: pool-id }) (err u200))))
    (begin
      (asserts! (is-eq (get status pool) TIMELOCK-ACTIVE) (err u201))
      (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
      (map-set pool-deposits 
        { pool-id: pool-id, depositor: tx-sender }
        (+ (default-to u0 (map-get? pool-deposits { pool-id: pool-id, depositor: tx-sender })) amount))
      (map-set timelocked-pools
        { pool-id: pool-id }
        (merge pool { total-locked: (+ (get total-locked pool) amount) }))
      (ok true))))



(define-constant RISK-LOW u1) 
(define-constant RISK-MEDIUM u2)
(define-constant RISK-HIGH u3)

(define-map risk-assessments
  { claim-id: uint }
  {
    risk-score: uint,
    factors: (list 5 (string-ascii 30)),
    assessed-by: principal,
    timestamp: uint
  }
)

(define-map risk-assessors principal bool)

(define-public (register-risk-assessor (assessor principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (map-set risk-assessors assessor true)
    (ok true)))

(define-public (assess-claim-risk 
    (claim-id uint) 
    (risk-score uint) 
    (risk-factors (list 5 (string-ascii 30))))
  (begin
    (asserts! (default-to false (map-get? risk-assessors tx-sender)) ERR-NOT-AUTHORIZED)
    (map-set risk-assessments
      { claim-id: claim-id }
      {
        risk-score: risk-score,
        factors: risk-factors,
        assessed-by: tx-sender,
        timestamp: stacks-block-height
      }
    )
    (ok true)))

(define-read-only (get-claim-risk-assessment (claim-id uint))
  (map-get? risk-assessments { claim-id: claim-id }))




  (define-constant BASE-PREMIUM-RATE u100)
(define-constant MAX-PREMIUM-MULTIPLIER u300)

(define-map user-claim-history 
    principal 
    { total-claims: uint, total-amount: uint, last-claim: uint }
)

(define-map risk-multipliers
    principal 
    uint
)

(define-public (calculate-premium (coverage-amount uint))
    (let (
        (user-history (default-to { total-claims: u0, total-amount: u0, last-claim: u0 } 
            (map-get? user-claim-history tx-sender)))
        (risk-score (+ u100 
            (* (get total-claims user-history) u50)))
        (final-multiplier (if (> risk-score MAX-PREMIUM-MULTIPLIER)
            MAX-PREMIUM-MULTIPLIER
            risk-score))
    )
    (begin
        (map-set risk-multipliers tx-sender final-multiplier)
        (ok (* coverage-amount (/ final-multiplier u100)))
    )))

(define-read-only (get-user-premium-rate (user principal))
    (default-to BASE-PREMIUM-RATE (map-get? risk-multipliers user)))


(define-constant REWARD-CYCLE-LENGTH u144)
(define-constant REWARD-RATE u50)

(define-map staking-positions
    principal
    { amount: uint, start-block: uint, last-claim: uint }
)

(define-map accumulated-rewards
    principal
    uint
)

(define-public (stake-tokens (amount uint))
    (let (
        (current-position (default-to { amount: u0, start-block: u0, last-claim: u0 }
            (map-get? staking-positions tx-sender)))
    )
    (begin
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (map-set staking-positions tx-sender
            {
                amount: (+ amount (get amount current-position)),
                start-block: stacks-block-height,
                last-claim: stacks-block-height
            })
        (ok true))))

(define-public (claim-staking-rewards)
    (let (
        (position (unwrap! (map-get? staking-positions tx-sender) ERR-NOT-AUTHORIZED))
        (cycles-passed (/ (- stacks-block-height (get last-claim position)) REWARD-CYCLE-LENGTH))
        (reward-amount (* (get amount position) (* cycles-passed REWARD-RATE)))
    )
    (begin
        (try! (as-contract (stx-transfer? reward-amount tx-sender tx-sender)))
        (map-set staking-positions tx-sender
            (merge position { last-claim: stacks-block-height }))
        (map-set accumulated-rewards tx-sender 
            (+ (default-to u0 (map-get? accumulated-rewards tx-sender)) reward-amount))
        (ok reward-amount))))