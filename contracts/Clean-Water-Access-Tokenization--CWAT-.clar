(define-fungible-token cwat-token)

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-unauthorized (err u101))
(define-constant err-not-found (err u102))
(define-constant err-already-exists (err u103))
(define-constant err-invalid-amount (err u104))
(define-constant err-insufficient-balance (err u105))
(define-constant err-emergency-resolved (err u106))

(define-data-var token-name (string-ascii 32) "Clean Water Access Token")
(define-data-var token-symbol (string-ascii 10) "CWAT")
(define-data-var token-decimals uint u6)
(define-data-var total-supply uint u0)
(define-data-var next-pump-id uint u1)
(define-data-var next-report-id uint u1)
(define-data-var next-audit-id uint u1)
(define-data-var next-emergency-id uint u1)

(define-map pump-stations uint {
    location: (string-ascii 100),
    operator: principal,
    status: (string-ascii 20),
    last-maintenance: uint,
    flow-rate: uint,
    water-quality: uint
})

(define-map technicians principal {
    name: (string-ascii 50),
    certification: (string-ascii 50),
    active: bool,
    reports-count: uint
})

(define-map sensor-data uint {
    pump-id: uint,
    timestamp: uint,
    flow-rate: uint,
    pressure: uint,
    temperature: uint,
    ph-level: uint,
    reporter: principal
})

(define-map community-reports uint {
    pump-id: uint,
    reporter: principal,
    timestamp: uint,
    water-available: bool,
    quality-rating: uint,
    description: (string-ascii 200),
    verified: bool,
    reward-paid: bool
})

(define-map quality-audits uint {
    pump-id: uint,
    auditor: principal,
    timestamp: uint,
    bacteria-count: uint,
    chemical-levels: uint,
    overall-rating: uint,
    certification-valid: bool
})

(define-map dao-proposals uint {
    proposer: principal,
    pump-id: uint,
    funding-amount: uint,
    description: (string-ascii 300),
    votes-for: uint,
    votes-against: uint,
    executed: bool,
    created-at: uint
})

(define-map user-votes {proposal-id: uint, voter: principal} bool)

(define-map emergency-alerts uint {
    pump-id: uint,
    reporter: principal,
    emergency-type: (string-ascii 50),
    severity-level: uint,
    description: (string-ascii 300),
    timestamp: uint,
    resolved: bool,
    responder: (optional principal),
    resolution-time: (optional uint)
})

(define-map emergency-responders principal {
    name: (string-ascii 50),
    contact: (string-ascii 100),
    active: bool,
    response-count: uint,
    average-response-time: uint
})

(define-public (mint-tokens (recipient principal) (amount uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> amount u0) err-invalid-amount)
        (try! (ft-mint? cwat-token amount recipient))
        (var-set total-supply (+ (var-get total-supply) amount))
        (ok true)
    )
)

(define-public (register-pump-station (location (string-ascii 100)) (operator principal))
    (let ((pump-id (var-get next-pump-id)))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set pump-stations pump-id {
            location: location,
            operator: operator,
            status: "active",
            last-maintenance: burn-block-height,
            flow-rate: u0,
            water-quality: u0
        })
        (var-set next-pump-id (+ pump-id u1))
        (ok pump-id)
    )
)

(define-public (register-technician (name (string-ascii 50)) (certification (string-ascii 50)))
    (begin
        (asserts! (is-none (map-get? technicians tx-sender)) err-already-exists)
        (map-set technicians tx-sender {
            name: name,
            certification: certification,
            active: true,
            reports-count: u0
        })
        (ok true)
    )
)

(define-public (log-sensor-data (pump-id uint) (flow-rate uint) (pressure uint) (temperature uint) (ph-level uint))
    (let ((data-id (var-get next-report-id)))
        (asserts! (is-some (map-get? pump-stations pump-id)) err-not-found)
        (asserts! (is-some (map-get? technicians tx-sender)) err-unauthorized)
        (map-set sensor-data data-id {
            pump-id: pump-id,
            timestamp: burn-block-height,
            flow-rate: flow-rate,
            pressure: pressure,
            temperature: temperature,
            ph-level: ph-level,
            reporter: tx-sender
        })
        (var-set next-report-id (+ data-id u1))
        (try! (ft-mint? cwat-token u10 tx-sender))
        (var-set total-supply (+ (var-get total-supply) u10))
        (ok data-id)
    )
)

(define-public (submit-community-report (pump-id uint) (water-available bool) (quality-rating uint) (description (string-ascii 200)))
    (let ((report-id (var-get next-report-id)))
        (asserts! (is-some (map-get? pump-stations pump-id)) err-not-found)
        (asserts! (<= quality-rating u10) err-invalid-amount)
        (map-set community-reports report-id {
            pump-id: pump-id,
            reporter: tx-sender,
            timestamp: burn-block-height,
            water-available: water-available,
            quality-rating: quality-rating,
            description: description,
            verified: false,
            reward-paid: false
        })
        (var-set next-report-id (+ report-id u1))
        (ok report-id)
    )
)

(define-public (verify-community-report (report-id uint))
    (let ((report (unwrap! (map-get? community-reports report-id) err-not-found)))
        (asserts! (is-some (map-get? technicians tx-sender)) err-unauthorized)
        (asserts! (not (get verified report)) err-already-exists)
        (map-set community-reports report-id (merge report {verified: true}))
        (if (not (get reward-paid report))
            (begin
                (try! (ft-mint? cwat-token u5 (get reporter report)))
                (var-set total-supply (+ (var-get total-supply) u5))
                (map-set community-reports report-id (merge report {verified: true, reward-paid: true}))
                (ok true)
            )
            (ok true)
        )
    )
)

(define-public (conduct-quality-audit (pump-id uint) (bacteria-count uint) (chemical-levels uint) (overall-rating uint))
    (let ((audit-id (var-get next-audit-id)))
        (asserts! (is-some (map-get? pump-stations pump-id)) err-not-found)
        (asserts! (is-some (map-get? technicians tx-sender)) err-unauthorized)
        (asserts! (<= overall-rating u10) err-invalid-amount)
        (map-set quality-audits audit-id {
            pump-id: pump-id,
            auditor: tx-sender,
            timestamp: burn-block-height,
            bacteria-count: bacteria-count,
            chemical-levels: chemical-levels,
            overall-rating: overall-rating,
            certification-valid: (>= overall-rating u7)
        })
        (var-set next-audit-id (+ audit-id u1))
        (try! (ft-mint? cwat-token u20 tx-sender))
        (var-set total-supply (+ (var-get total-supply) u20))
        (ok audit-id)
    )
)

(define-public (create-dao-proposal (pump-id uint) (funding-amount uint) (description (string-ascii 300)))
    (let ((proposal-id (var-get next-audit-id)))
        (asserts! (is-some (map-get? pump-stations pump-id)) err-not-found)
        (asserts! (> funding-amount u0) err-invalid-amount)
        (asserts! (>= (ft-get-balance cwat-token tx-sender) u100) err-insufficient-balance)
        (map-set dao-proposals proposal-id {
            proposer: tx-sender,
            pump-id: pump-id,
            funding-amount: funding-amount,
            description: description,
            votes-for: u0,
            votes-against: u0,
            executed: false,
            created-at: burn-block-height
        })
        (var-set next-audit-id (+ proposal-id u1))
        (ok proposal-id)
    )
)

(define-public (vote-on-proposal (proposal-id uint) (support bool))
    (let ((proposal (unwrap! (map-get? dao-proposals proposal-id) err-not-found))
          (voter-balance (ft-get-balance cwat-token tx-sender)))
        (asserts! (> voter-balance u0) err-insufficient-balance)
        (asserts! (is-none (map-get? user-votes {proposal-id: proposal-id, voter: tx-sender})) err-already-exists)
        (asserts! (not (get executed proposal)) err-already-exists)
        (map-set user-votes {proposal-id: proposal-id, voter: tx-sender} true)
        (if support
            (map-set dao-proposals proposal-id (merge proposal {votes-for: (+ (get votes-for proposal) voter-balance)}))
            (map-set dao-proposals proposal-id (merge proposal {votes-against: (+ (get votes-against proposal) voter-balance)}))
        )
        (ok true)
    )
)

(define-public (execute-proposal (proposal-id uint))
    (let ((proposal (unwrap! (map-get? dao-proposals proposal-id) err-not-found)))
        (asserts! (not (get executed proposal)) err-already-exists)
        (asserts! (> (get votes-for proposal) (get votes-against proposal)) err-unauthorized)
        (asserts! (>= (- burn-block-height (get created-at proposal)) u144) err-unauthorized)
        (map-set dao-proposals proposal-id (merge proposal {executed: true}))
        (ok true)
    )
)

(define-public (update-pump-status (pump-id uint) (new-status (string-ascii 20)))
    (let ((pump (unwrap! (map-get? pump-stations pump-id) err-not-found)))
        (asserts! (or (is-eq tx-sender contract-owner) (is-eq tx-sender (get operator pump))) err-unauthorized)
        (map-set pump-stations pump-id (merge pump {status: new-status, last-maintenance: burn-block-height}))
        (ok true)
    )
)

(define-public (register-emergency-responder (name (string-ascii 50)) (contact (string-ascii 100)))
    (begin
        (asserts! (is-none (map-get? emergency-responders tx-sender)) err-already-exists)
        (map-set emergency-responders tx-sender {
            name: name,
            contact: contact,
            active: true,
            response-count: u0,
            average-response-time: u0
        })
        (ok true)
    )
)

(define-public (report-emergency (pump-id uint) (emergency-type (string-ascii 50)) (severity-level uint) (description (string-ascii 300)))
    (let ((emergency-id (var-get next-emergency-id)))
        (asserts! (is-some (map-get? pump-stations pump-id)) err-not-found)
        (asserts! (<= severity-level u5) err-invalid-amount)
        (asserts! (> severity-level u0) err-invalid-amount)
        (map-set emergency-alerts emergency-id {
            pump-id: pump-id,
            reporter: tx-sender,
            emergency-type: emergency-type,
            severity-level: severity-level,
            description: description,
            timestamp: burn-block-height,
            resolved: false,
            responder: none,
            resolution-time: none
        })
        (var-set next-emergency-id (+ emergency-id u1))
        (let ((reward-amount (* severity-level u15)))
            (try! (ft-mint? cwat-token reward-amount tx-sender))
            (var-set total-supply (+ (var-get total-supply) reward-amount))
        )
        (ok emergency-id)
    )
)

(define-public (respond-to-emergency (emergency-id uint))
    (let ((alert (unwrap! (map-get? emergency-alerts emergency-id) err-not-found)))
        (asserts! (is-some (map-get? emergency-responders tx-sender)) err-unauthorized)
        (asserts! (not (get resolved alert)) err-emergency-resolved)
        (asserts! (is-none (get responder alert)) err-already-exists)
        (map-set emergency-alerts emergency-id (merge alert {responder: (some tx-sender)}))
        (let ((base-reward u50)
              (severity-bonus (* (get severity-level alert) u10)))
            (try! (ft-mint? cwat-token (+ base-reward severity-bonus) tx-sender))
            (var-set total-supply (+ (var-get total-supply) (+ base-reward severity-bonus)))
        )
        (ok true)
    )
)

(define-public (resolve-emergency (emergency-id uint))
    (let ((alert (unwrap! (map-get? emergency-alerts emergency-id) err-not-found))
          (responder-principal (unwrap! (get responder alert) err-unauthorized)))
        (asserts! (is-eq tx-sender responder-principal) err-unauthorized)
        (asserts! (not (get resolved alert)) err-emergency-resolved)
        (let ((response-time (- burn-block-height (get timestamp alert)))
              (responder-data (unwrap! (map-get? emergency-responders tx-sender) err-not-found)))
            (map-set emergency-alerts emergency-id (merge alert {
                resolved: true,
                resolution-time: (some response-time)
            }))
            (let ((new-count (+ (get response-count responder-data) u1))
                  (total-time (+ (* (get average-response-time responder-data) (get response-count responder-data)) response-time))
                  (new-average (/ total-time new-count)))
                (map-set emergency-responders tx-sender (merge responder-data {
                    response-count: new-count,
                    average-response-time: new-average
                }))
            )
            (let ((completion-bonus u25)
                  (speed-bonus (if (<= response-time u10) u25 u0)))
                (try! (ft-mint? cwat-token (+ completion-bonus speed-bonus) tx-sender))
                (var-set total-supply (+ (var-get total-supply) (+ completion-bonus speed-bonus)))
            )
        )
        (ok true)
    )
)

(define-read-only (get-pump-station (pump-id uint))
    (map-get? pump-stations pump-id)
)

(define-read-only (get-technician (technician principal))
    (map-get? technicians technician)
)

(define-read-only (get-sensor-data (data-id uint))
    (map-get? sensor-data data-id)
)

(define-read-only (get-community-report (report-id uint))
    (map-get? community-reports report-id)
)

(define-read-only (get-quality-audit (audit-id uint))
    (map-get? quality-audits audit-id)
)

(define-read-only (get-dao-proposal (proposal-id uint))
    (map-get? dao-proposals proposal-id)
)

(define-read-only (get-token-info)
    {
        name: (var-get token-name),
        symbol: (var-get token-symbol),
        decimals: (var-get token-decimals),
        total-supply: (var-get total-supply)
    }
)

(define-read-only (get-balance (account principal))
    (ft-get-balance cwat-token account)
)

(define-read-only (get-emergency-alert (emergency-id uint))
    (map-get? emergency-alerts emergency-id)
)

(define-read-only (get-emergency-responder (responder principal))
    (map-get? emergency-responders responder)
)

(define-read-only (get-active-emergencies (pump-id uint))
    (let ((emergency-1 (map-get? emergency-alerts u1))
          (emergency-2 (map-get? emergency-alerts u2))
          (emergency-3 (map-get? emergency-alerts u3)))
        {
            pump-emergencies: pump-id,
            total-active: (+ 
                (if (and (is-some emergency-1) (is-eq (get pump-id (unwrap-panic emergency-1)) pump-id) (not (get resolved (unwrap-panic emergency-1)))) u1 u0)
                (+ (if (and (is-some emergency-2) (is-eq (get pump-id (unwrap-panic emergency-2)) pump-id) (not (get resolved (unwrap-panic emergency-2)))) u1 u0)
                   (if (and (is-some emergency-3) (is-eq (get pump-id (unwrap-panic emergency-3)) pump-id) (not (get resolved (unwrap-panic emergency-3)))) u1 u0))
            )
        }
    )
)

(define-data-var community-fund uint u0)

(define-map token-stakes principal {
    amount: uint,
    start-time: uint,
    claimed-rewards: uint
})

(define-public (stake-tokens (amount uint))
    (let ((current-stake (default-to {amount: u0, start-time: u0, claimed-rewards: u0} (map-get? token-stakes tx-sender))))
        (asserts! (> amount u0) err-invalid-amount)
        (asserts! (>= (ft-get-balance cwat-token tx-sender) amount) err-insufficient-balance)
        (try! (ft-transfer? cwat-token amount tx-sender (as-contract tx-sender)))
        (map-set token-stakes tx-sender {
            amount: (+ (get amount current-stake) amount),
            start-time: (if (is-eq (get start-time current-stake) u0) burn-block-height (get start-time current-stake)),
            claimed-rewards: (get claimed-rewards current-stake)
        })
        (ok true)
    )
)

(define-public (unstake-tokens (amount uint))
    (let ((current-stake (unwrap! (map-get? token-stakes tx-sender) err-not-found)))
        (asserts! (>= (get amount current-stake) amount) err-insufficient-balance)
        (asserts! (>= (- burn-block-height (get start-time current-stake)) u1440) err-unauthorized)
        (try! (as-contract (ft-transfer? cwat-token amount tx-sender tx-sender)))
        (map-set token-stakes tx-sender {
            amount: (- (get amount current-stake) amount),
            start-time: (get start-time current-stake),
            claimed-rewards: (get claimed-rewards current-stake)
        })
        (ok true)
    )
)

(define-read-only (calculate-staking-rewards (account principal))
    (let ((stake (default-to {amount: u0, start-time: u0, claimed-rewards: u0} (map-get? token-stakes account)))
          (duration (- burn-block-height (get start-time stake)))
          (base-reward (/ (* (get amount stake) duration) u100000)))
        (if (> duration u0) base-reward u0)
    )
)

(define-public (claim-staking-rewards)
    (let ((stake (unwrap! (map-get? token-stakes tx-sender) err-not-found))
          (rewards (calculate-staking-rewards tx-sender))
          (unclaimed (- rewards (get claimed-rewards stake))))
        (asserts! (> unclaimed u0) err-invalid-amount)
        (try! (ft-mint? cwat-token unclaimed tx-sender))
        (var-set total-supply (+ (var-get total-supply) unclaimed))
        (map-set token-stakes tx-sender (merge stake {claimed-rewards: rewards}))
        (ok unclaimed)
    )
)

(define-public (transfer-tokens (recipient principal) (amount uint))
    (let ((fee (/ amount u100))
          (transfer-amount (- amount fee)))
        (asserts! (> amount u0) err-invalid-amount)
        (asserts! (>= (ft-get-balance cwat-token tx-sender) amount) err-insufficient-balance)
        (try! (ft-transfer? cwat-token transfer-amount tx-sender recipient))
        (var-set community-fund (+ (var-get community-fund) fee))
        (ok true)
    )
)

(define-read-only (get-community-fund)
    (var-get community-fund)
)

(define-read-only (get-stake-info (account principal))
    (map-get? token-stakes account)
)
