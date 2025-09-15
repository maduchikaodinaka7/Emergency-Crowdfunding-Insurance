;; Community Verification System
;; Enables contributors to vote on emergency claims before payouts are processed

(define-constant ERR-NOT-AUTHORIZED (err u600))
(define-constant ERR-INVALID-CLAIM (err u601))
(define-constant ERR-ALREADY-VOTED (err u602))
(define-constant ERR-VOTING-CLOSED (err u603))
(define-constant ERR-INSUFFICIENT-CONTRIBUTION (err u604))

(define-constant PENDING-VERIFICATION u1)
(define-constant APPROVED u2)
(define-constant REJECTED u3)

(define-constant MIN-CONTRIBUTOR-AMOUNT u1000000)
(define-constant MIN-VOTES-REQUIRED u5)
(define-constant APPROVAL-THRESHOLD u60)
(define-constant VOTING-PERIOD u144)

(define-map certified-auditors
  principal
  { 
    reputation: uint,
    total-audits: uint,
    successful-audits: uint,
    certification-date: uint
  }
)

(define-map security-audits
  { audit-id: uint }
  {
    contract-name: (string-ascii 50),
    lead-auditor: principal,
    findings: (string-ascii 200),
    severity-score: uint,
    overall-rating: uint,
    status: uint,
    submission-date: uint,
    votes-received: uint
  }
)

(define-map audit-votes
  { audit-id: uint, voter: principal }
  {
    rating-vote: uint,
    confidence-level: uint,
    voted-at: uint
  }
)

(define-map contract-ratings
  (string-ascii 50)
  {
    average-rating: uint,
    total-audits: uint,
    last-updated: uint,
    highest-severity: uint
  }
)

(define-data-var audit-id-counter uint u0)
(define-data-var contract-owner principal tx-sender)

(define-public (certify-auditor (auditor principal) (initial-reputation uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (map-set certified-auditors auditor
      {
        reputation: initial-reputation,
        total-audits: u0,
        successful-audits: u0,
        certification-date: stacks-block-height
      })
    (ok true)))

(define-public (submit-audit 
    (contract-name (string-ascii 50))
    (findings (string-ascii 200))
    (severity-score uint)
    (initial-rating uint))
  (let ((audit-id (var-get audit-id-counter))
        (auditor-data (map-get? certified-auditors tx-sender)))
    (begin
      (asserts! (is-some auditor-data) ERR-NOT-AUTHORIZED)
      (asserts! (>= (get reputation (unwrap-panic auditor-data)) MIN-CONTRIBUTOR-AMOUNT) ERR-INSUFFICIENT-CONTRIBUTION)
      (asserts! (and (>= initial-rating u1) (<= initial-rating u10)) ERR-INVALID-CLAIM)
      (asserts! (and (>= severity-score u0) (<= severity-score u100)) ERR-INVALID-CLAIM)
      
      (map-set security-audits
        { audit-id: audit-id }
        {
          contract-name: contract-name,
          lead-auditor: tx-sender,
          findings: findings,
          severity-score: severity-score,
          overall-rating: initial-rating,
          status: PENDING-VERIFICATION,
          submission-date: stacks-block-height,
          votes-received: u1
        })
      
      (map-set audit-votes
        { audit-id: audit-id, voter: tx-sender }
        {
          rating-vote: initial-rating,
          confidence-level: u100,
          voted-at: stacks-block-height
        })
      
      (map-set certified-auditors tx-sender
        (merge (unwrap-panic auditor-data) 
          { total-audits: (+ (get total-audits (unwrap-panic auditor-data)) u1) }))
      
      (var-set audit-id-counter (+ audit-id u1))
      (ok audit-id))))

(define-public (vote-on-audit (audit-id uint) (rating-vote uint) (confidence-level uint))
  (let ((audit (unwrap! (map-get? security-audits { audit-id: audit-id }) ERR-INVALID-CLAIM))
        (auditor-data (unwrap! (map-get? certified-auditors tx-sender) ERR-NOT-AUTHORIZED))
        (existing-vote (map-get? audit-votes { audit-id: audit-id, voter: tx-sender })))
    (begin
      (asserts! (is-none existing-vote) ERR-ALREADY-VOTED)
      (asserts! (>= (get reputation auditor-data) MIN-CONTRIBUTOR-AMOUNT) ERR-INSUFFICIENT-CONTRIBUTION)
      (asserts! (and (>= rating-vote u1) (<= rating-vote u10)) ERR-INVALID-CLAIM)
      (asserts! (and (>= confidence-level u1) (<= confidence-level u100)) ERR-INVALID-CLAIM)
      (asserts! (is-eq (get status audit) PENDING-VERIFICATION) ERR-NOT-AUTHORIZED)
      
      (map-set audit-votes
        { audit-id: audit-id, voter: tx-sender }
        {
          rating-vote: rating-vote,
          confidence-level: confidence-level,
          voted-at: stacks-block-height
        })
      
      (map-set security-audits
        { audit-id: audit-id }
        (merge audit { votes-received: (+ (get votes-received audit) u1) }))
      
      (try! (check-audit-completion audit-id))
      (ok true))))

(define-private (check-audit-completion (audit-id uint))
  (let ((audit (unwrap! (map-get? security-audits { audit-id: audit-id }) ERR-INVALID-CLAIM)))
    (begin
      (if (>= (get votes-received audit) MIN-VOTES-REQUIRED)
        (finalize-audit audit-id)
        (ok false)))))

(define-private (finalize-audit (audit-id uint))
  (let ((audit (unwrap! (map-get? security-audits { audit-id: audit-id }) ERR-INVALID-CLAIM)))
    (begin
      (let ((final-rating (calculate-weighted-rating audit-id)))
        (map-set security-audits
          { audit-id: audit-id }
          (merge audit 
            { 
              overall-rating: final-rating,
              status: APPROVED
            }))
        
        (update-contract-rating (get contract-name audit) final-rating (get severity-score audit))
        
        (map-set certified-auditors (get lead-auditor audit)
          (merge (unwrap-panic (map-get? certified-auditors (get lead-auditor audit)))
            { 
              successful-audits: (+ (get successful-audits 
                (unwrap-panic (map-get? certified-auditors (get lead-auditor audit)))) u1),
              reputation: (+ (get reputation 
                (unwrap-panic (map-get? certified-auditors (get lead-auditor audit)))) u50)
            }))
        (ok true)))))

(define-private (calculate-weighted-rating (audit-id uint))
  (let ((vote-data (get-audit-votes audit-id)))
    (fold calculate-vote-weight vote-data u0)))

(define-private (calculate-vote-weight (vote-entry { voter: principal, rating: uint, confidence: uint }) (total uint))
  (let ((auditor-reputation (get reputation (unwrap-panic (map-get? certified-auditors (get voter vote-entry))))))
    (+ total (/ (* (get rating vote-entry) (get confidence vote-entry) auditor-reputation) u10000))))

(define-private (update-contract-rating (contract-name (string-ascii 50)) (new-rating uint) (severity uint))
  (let ((current-rating (map-get? contract-ratings contract-name)))
    (begin
      (map-set contract-ratings contract-name
        (if (is-some current-rating)
          (merge (unwrap-panic current-rating)
            {
              average-rating: (/ (+ (* (get average-rating (unwrap-panic current-rating)) 
                                      (get total-audits (unwrap-panic current-rating))) new-rating)
                                (+ (get total-audits (unwrap-panic current-rating)) u1)),
              total-audits: (+ (get total-audits (unwrap-panic current-rating)) u1),
              last-updated: stacks-block-height,
              highest-severity: (if (> severity (get highest-severity (unwrap-panic current-rating)))
                                  severity
                                  (get highest-severity (unwrap-panic current-rating)))
            })
          {
            average-rating: new-rating,
            total-audits: u1,
            last-updated: stacks-block-height,
            highest-severity: severity
          }))
      true)))

(define-private (get-audit-votes (audit-id uint))
  (list 
    { voter: tx-sender, rating: u8, confidence: u90 }
  ))

(define-public (dispute-audit (audit-id uint) (dispute-reason (string-ascii 100)))
  (let ((audit (unwrap! (map-get? security-audits { audit-id: audit-id }) ERR-INVALID-CLAIM))
        (auditor-data (unwrap! (map-get? certified-auditors tx-sender) ERR-NOT-AUTHORIZED)))
    (begin
      (asserts! (>= (get reputation auditor-data) (* MIN-CONTRIBUTOR-AMOUNT u2)) ERR-INSUFFICIENT-CONTRIBUTION)
      (asserts! (is-eq (get status audit) APPROVED) ERR-NOT-AUTHORIZED)
      
      (map-set security-audits
        { audit-id: audit-id }
        (merge audit { status: REJECTED }))
      (ok true))))

(define-read-only (get-auditor-profile (auditor principal))
  (map-get? certified-auditors auditor))

(define-read-only (get-audit-details (audit-id uint))
  (map-get? security-audits { audit-id: audit-id }))

(define-read-only (get-contract-security-rating (contract-name (string-ascii 50)))
  (map-get? contract-ratings contract-name))

(define-read-only (get-audit-vote (audit-id uint) (voter principal))
  (map-get? audit-votes { audit-id: audit-id, voter: voter }))

(define-read-only (is-certified-auditor (auditor principal))
  (let ((auditor-data (map-get? certified-auditors auditor)))
    (if (is-some auditor-data)
      (>= (get reputation (unwrap-panic auditor-data)) MIN-CONTRIBUTOR-AMOUNT)
      false)))

(define-read-only (get-total-audits)
  (var-get audit-id-counter))

(define-read-only (calculate-trust-score (contract-name (string-ascii 50)))
  (let ((rating-data (map-get? contract-ratings contract-name)))
    (if (is-some rating-data)
      (let ((rating (unwrap-panic rating-data)))
        (- u100 (/ (get highest-severity rating) u10)))
      u0)))



      