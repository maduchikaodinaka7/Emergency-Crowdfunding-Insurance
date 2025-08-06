;; Dynamic Coverage Calculator
;; Automatically adjusts insurance premiums and coverage based on risk factors

;; Constants
(define-constant ERR-NOT-AUTHORIZED (err u900))
(define-constant ERR-INVALID-LOCATION (err u901))
(define-constant ERR-INVALID-RISK-SCORE (err u902))
(define-constant ERR-COVERAGE-LIMIT-EXCEEDED (err u903))
(define-constant ERR-INSUFFICIENT-HISTORY (err u904))
(define-constant ERR-ORACLE-NOT-FOUND (err u905))

;; Risk level constants
(define-constant RISK-MINIMAL u10)
(define-constant RISK-LOW u25)
(define-constant RISK-MODERATE u50)
(define-constant RISK-HIGH u75)
(define-constant RISK-EXTREME u100)

;; Base coverage and premium rates
(define-constant BASE-PREMIUM-RATE u100) ;; 1%
(define-constant MAX-COVERAGE-MULTIPLIER u500) ;; 5x base coverage
(define-constant BASE-COVERAGE-AMOUNT u10000000) ;; 10 STX

;; Geographic risk zones
(define-map risk-zones
  (string-ascii 30)
  {
    flood-risk: uint,
    earthquake-risk: uint,
    wildfire-risk: uint,
    hurricane-risk: uint,
    overall-multiplier: uint
  }
)

;; User coverage profiles
(define-map user-coverage-profiles
  principal
  {
    location: (string-ascii 30),
    base-coverage: uint,
    premium-rate: uint,
    coverage-multiplier: uint,
    last-updated: uint,
    risk-score: uint
  }
)

;; Historical claims data for risk calculation
(define-map location-claim-history
  (string-ascii 30)
  {
    total-claims: uint,
    total-amount: uint,
    frequency-score: uint,
    severity-score: uint,
    last-major-event: uint
  }
)

;; Market volatility factors
(define-map market-conditions
  uint ;; block-height ranges
  {
    volatility-index: uint,
    liquidity-factor: uint,
    demand-multiplier: uint,
    supply-adjustment: uint
  }
)

;; Oracle data feeds for external risk factors
(define-map authorized-risk-oracles principal bool)
(define-map oracle-risk-feeds
  { oracle: principal, data-type: (string-ascii 20) }
  {
    risk-value: uint,
    confidence-level: uint,
    last-updated: uint,
    data-source: (string-ascii 50)
  }
)

;; Data variables
(define-data-var contract-owner principal tx-sender)
(define-data-var global-risk-multiplier uint u100)
(define-data-var market-volatility uint u100)
(define-data-var coverage-calculation-fee uint u10000) ;; 0.01 STX

;; Public Functions

;; Initialize risk zone data
(define-public (set-risk-zone 
    (location (string-ascii 30))
    (flood-risk uint)
    (earthquake-risk uint)
    (wildfire-risk uint)
    (hurricane-risk uint))
  (let ((overall-multiplier (/ (+ flood-risk earthquake-risk wildfire-risk hurricane-risk) u4)))
    (begin
      (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
      (asserts! (and (<= flood-risk u100) (<= earthquake-risk u100) 
                     (<= wildfire-risk u100) (<= hurricane-risk u100)) ERR-INVALID-RISK-SCORE)
      (map-set risk-zones location
        {
          flood-risk: flood-risk,
          earthquake-risk: earthquake-risk,
          wildfire-risk: wildfire-risk,
          hurricane-risk: hurricane-risk,
          overall-multiplier: overall-multiplier
        })
      (ok true))))

;; Add authorized risk oracle
(define-public (authorize-risk-oracle (oracle principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (map-set authorized-risk-oracles oracle true)
    (ok true)))

;; Oracle submits risk data
(define-public (submit-risk-data 
    (data-type (string-ascii 20))
    (risk-value uint)
    (confidence-level uint)
    (data-source (string-ascii 50)))
  (begin
    (asserts! (default-to false (map-get? authorized-risk-oracles tx-sender)) ERR-NOT-AUTHORIZED)
    (asserts! (<= risk-value u100) ERR-INVALID-RISK-SCORE)
    (asserts! (and (>= confidence-level u1) (<= confidence-level u100)) ERR-INVALID-RISK-SCORE)
    (map-set oracle-risk-feeds
      { oracle: tx-sender, data-type: data-type }
      {
        risk-value: risk-value,
        confidence-level: confidence-level,
        last-updated: stacks-block-height,
        data-source: data-source
      })
    (ok true)))

;; Calculate dynamic coverage for a user
(define-public (calculate-coverage (location (string-ascii 30)) (requested-coverage uint))
  (let (
    (zone-data (unwrap! (map-get? risk-zones location) ERR-INVALID-LOCATION))
    (claim-history (default-to 
      { total-claims: u0, total-amount: u0, frequency-score: u0, severity-score: u0, last-major-event: u0 }
      (map-get? location-claim-history location)))
    (user-risk-score (calculate-user-risk-score tx-sender location))
    (market-adjustment (calculate-market-adjustment))
    (base-premium (calculate-base-premium requested-coverage user-risk-score))
    (adjusted-premium (adjust-premium-for-market base-premium market-adjustment))
    (coverage-multiplier (calculate-coverage-multiplier user-risk-score (get overall-multiplier zone-data)))
    (final-coverage (if (<= requested-coverage (* BASE-COVERAGE-AMOUNT coverage-multiplier))
                        requested-coverage
                        (* BASE-COVERAGE-AMOUNT coverage-multiplier)))
  )
  (begin
    (try! (stx-transfer? (var-get coverage-calculation-fee) tx-sender (as-contract tx-sender)))
    (map-set user-coverage-profiles tx-sender
      {
        location: location,
        base-coverage: final-coverage,
        premium-rate: adjusted-premium,
        coverage-multiplier: coverage-multiplier,
        last-updated: stacks-block-height,
        risk-score: user-risk-score
      })
    (ok { coverage: final-coverage, premium-rate: adjusted-premium, risk-score: user-risk-score }))))

;; Update claim history for location-based risk assessment
(define-public (update-claim-history 
    (location (string-ascii 30))
    (claim-amount uint)
    (is-major-event bool))
  (let (
    (current-history (default-to 
      { total-claims: u0, total-amount: u0, frequency-score: u0, severity-score: u0, last-major-event: u0 }
      (map-get? location-claim-history location)))
    (new-frequency (+ (get total-claims current-history) u1))
    (new-total (+ (get total-amount current-history) claim-amount))
    (frequency-score (if (<= (/ (* new-frequency u100) u50) u100)
                         (/ (* new-frequency u100) u50)
                         u100)) ;; Cap at 100, normalize to 50 claims max
    (severity-score (if (<= (/ new-total u100000000) u100)
                        (/ new-total u100000000)
                        u100)) ;; Normalize to 100 STX max
  )
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (map-set location-claim-history location
      {
        total-claims: new-frequency,
        total-amount: new-total,
        frequency-score: frequency-score,
        severity-score: severity-score,
        last-major-event: (if is-major-event stacks-block-height (get last-major-event current-history))
      })
    (ok true))))

;; Set global market conditions
(define-public (update-market-conditions 
    (volatility-index uint)
    (liquidity-factor uint)
    (demand-multiplier uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (and (<= volatility-index u200) (<= liquidity-factor u200) 
                   (<= demand-multiplier u200)) ERR-INVALID-RISK-SCORE)
    (var-set market-volatility volatility-index)
    (map-set market-conditions stacks-block-height
      {
        volatility-index: volatility-index,
        liquidity-factor: liquidity-factor,
        demand-multiplier: demand-multiplier,
        supply-adjustment: (calculate-supply-adjustment liquidity-factor demand-multiplier)
      })
    (ok true)))

;; Private helper functions

;; Calculate user-specific risk score
(define-private (calculate-user-risk-score (user principal) (location (string-ascii 30)))
  (let (
    (zone-data (default-to 
      { flood-risk: u50, earthquake-risk: u50, wildfire-risk: u50, hurricane-risk: u50, overall-multiplier: u50 }
      (map-get? risk-zones location)))
    (claim-history (default-to 
      { total-claims: u0, total-amount: u0, frequency-score: u0, severity-score: u0, last-major-event: u0 }
      (map-get? location-claim-history location)))
    (geographic-risk (get overall-multiplier zone-data))
    (frequency-risk (get frequency-score claim-history))
    (severity-risk (get severity-score claim-history))
    (recency-risk (calculate-recency-risk (get last-major-event claim-history)))
  )
  (/ (+ geographic-risk frequency-risk severity-risk recency-risk) u4)))

;; Calculate recency risk based on last major event
(define-private (calculate-recency-risk (last-major-event uint))
  (if (is-eq last-major-event u0)
    u20  ;; Low risk if no major events
    (let ((blocks-since (- stacks-block-height last-major-event)))
      (if (< blocks-since u1000)  ;; Recent event (< ~1 week)
        u80
        (if (< blocks-since u5000)  ;; Moderate (< ~1 month)
          u50
          u20)))))  ;; Old event

;; Calculate base premium based on coverage and risk
(define-private (calculate-base-premium (coverage uint) (risk-score uint))
  (let ((risk-multiplier (+ u100 risk-score)))  ;; 100% + risk percentage
    (/ (* coverage risk-multiplier) u10000)))  ;; Convert to basis points

;; Calculate market adjustment factor
(define-private (calculate-market-adjustment)
  (let ((current-volatility (var-get market-volatility)))
    (+ u100 (/ current-volatility u2))))  ;; Add half the volatility as adjustment

;; Adjust premium for market conditions
(define-private (adjust-premium-for-market (base-premium uint) (market-adjustment uint))
  (/ (* base-premium market-adjustment) u100))

;; Calculate coverage multiplier based on risk
(define-private (calculate-coverage-multiplier (risk-score uint) (zone-multiplier uint))
  (let ((combined-risk (/ (+ risk-score zone-multiplier) u2)))
    (if (<= combined-risk RISK-MINIMAL) 
        u500  ;; 5x coverage for minimal risk
        (if (<= combined-risk RISK-LOW)
            u400  ;; 4x coverage for low risk
            (if (<= combined-risk RISK-MODERATE)
                u300  ;; 3x coverage for moderate risk
                (if (<= combined-risk RISK-HIGH)
                    u200  ;; 2x coverage for high risk
                    u100))))))

;; Calculate supply adjustment based on liquidity and demand
(define-private (calculate-supply-adjustment (liquidity uint) (demand uint))
  (if (> demand liquidity)
    (+ u100 (/ (- demand liquidity) u2))  ;; Increase if demand > liquidity
    (- u100 (/ (- liquidity demand) u4))))  ;; Decrease if liquidity > demand

;; Read-only functions

;; Get user coverage profile
(define-read-only (get-user-coverage-profile (user principal))
  (map-get? user-coverage-profiles user))

;; Get risk zone data
(define-read-only (get-risk-zone-data (location (string-ascii 30)))
  (map-get? risk-zones location))

;; Get location claim history
(define-read-only (get-location-claims (location (string-ascii 30)))
  (map-get? location-claim-history location))

;; Get oracle risk data
(define-read-only (get-oracle-risk-data (oracle principal) (data-type (string-ascii 20)))
  (map-get? oracle-risk-feeds { oracle: oracle, data-type: data-type }))

;; Get current market conditions
(define-read-only (get-current-market-conditions)
  (map-get? market-conditions stacks-block-height))

;; Check if oracle is authorized
(define-read-only (is-authorized-oracle (oracle principal))
  (default-to false (map-get? authorized-risk-oracles oracle)))

;; Calculate quote without updating user profile
(define-read-only (get-coverage-quote (user principal) (location (string-ascii 30)) (requested-coverage uint))
  (let (
    (zone-data (map-get? risk-zones location))
    (user-risk-score (calculate-user-risk-score user location))
    (market-adjustment (calculate-market-adjustment))
    (base-premium (calculate-base-premium requested-coverage user-risk-score))
    (adjusted-premium (adjust-premium-for-market base-premium market-adjustment))
  )
  (if (is-some zone-data)
    (some { 
      estimated-premium: adjusted-premium, 
      risk-score: user-risk-score,
      market-adjustment: market-adjustment 
    })
    none)))

