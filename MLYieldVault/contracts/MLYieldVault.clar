;; ML-Enhanced Yield Optimizer Contract
;; This contract implements a yield optimizer with machine learning-inspired strategy selection.
;; It uses weighted scoring, historical performance tracking, and dynamic risk assessment
;; to optimize yield allocation across multiple DeFi strategies.

;; constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-AMOUNT (err u101))
(define-constant ERR-INSUFFICIENT-BALANCE (err u102))
(define-constant ERR-STRATEGY-NOT-FOUND (err u103))
(define-constant ERR-INVALID-WEIGHT (err u104))
(define-constant ERR-STRATEGY-PAUSED (err u105))
(define-constant MAX-STRATEGIES u10)
(define-constant PRECISION-FACTOR u1000000) ;; 6 decimal precision
(define-constant MIN-DEPOSIT u1000000) ;; 1 STX minimum

;; data maps and vars
(define-data-var total-value-locked uint u0)
(define-data-var strategy-count uint u0)
(define-data-var ml-learning-rate uint u50) ;; 0.05% learning rate scaled by PRECISION-FACTOR

;; User position tracking
(define-map user-deposits
    principal
    {
        amount: uint,
        shares: uint,
        entry-block: uint,
        strategy-allocation: (list 10 uint)
    }
)

;; Strategy configuration with ML weights
(define-map strategies
    uint
    {
        name: (string-ascii 50),
        apy-prediction: uint, ;; Predicted APY scaled by PRECISION-FACTOR
        risk-score: uint, ;; 0-100 risk score
        ml-weight: uint, ;; ML-calculated allocation weight
        performance-history: (list 5 uint), ;; Last 5 performance snapshots
        total-allocated: uint,
        is-active: bool,
        confidence-score: uint ;; ML confidence 0-100
    }
)

;; Historical performance for ML training
(define-map performance-metrics
    {strategy-id: uint, epoch: uint}
    {
        actual-apy: uint,
        prediction-error: uint,
        sharpe-ratio: uint,
        timestamp: uint
    }
)

;; Global ML parameters
(define-data-var current-epoch uint u0)
(define-data-var total-shares uint u0)

;; private functions

;; Calculate shares based on current TVL and deposit amount
(define-private (calculate-shares (amount uint))
    (let
        (
            (tvl (var-get total-value-locked))
            (shares (var-get total-shares))
        )
        (if (is-eq tvl u0)
            amount ;; First deposit: 1:1 ratio
            (/ (* amount shares) tvl) ;; Subsequent: proportional to TVL
        )
    )
)

;; Update ML weight based on performance (simplified gradient descent)
(define-private (update-strategy-weight (strategy-id uint) (performance-delta int))
    (let
        (
            (strategy (unwrap! (map-get? strategies strategy-id) false))
            (learning-rate (var-get ml-learning-rate))
            (current-weight (get ml-weight strategy))
            (adjustment (if (> performance-delta 0)
                           (/ (* current-weight learning-rate) PRECISION-FACTOR)
                           (/ (* current-weight learning-rate) (* PRECISION-FACTOR u2))))
            (new-weight (if (> performance-delta 0)
                          (+ current-weight adjustment)
                          (if (> current-weight adjustment)
                              (- current-weight adjustment)
                              u1)))
        )
        (map-set strategies strategy-id
            (merge strategy {ml-weight: new-weight})
        )
        true
    )
)

;; Helper function: return minimum of two uints
(define-private (min-uint (a uint) (b uint))
    (if (<= a b) a b)
)

;; Helper function: return maximum of two uints
(define-private (max-uint (a uint) (b uint))
    (if (>= a b) a b)
)

;; Calculate risk-adjusted return score
(define-private (calculate-risk-adjusted-score (apy uint) (risk uint) (confidence uint))
    (let
        (
            (risk-penalty (/ (* risk PRECISION-FACTOR) u100))
            (confidence-boost (/ (* confidence PRECISION-FACTOR) u100))
            (adjusted-apy (/ (* apy confidence-boost) PRECISION-FACTOR))
        )
        (if (> adjusted-apy risk-penalty)
            (- adjusted-apy risk-penalty)
            u0
        )
    )
)

;; Softmax-inspired weight normalization
(define-private (normalize-weights (strategy-weights (list 10 uint)))
    (let
        (
            (total-weight (fold + strategy-weights u0))
        )
        (if (is-eq total-weight u0)
            strategy-weights
            (map normalize-single-weight strategy-weights)
        )
    )
)

(define-private (normalize-single-weight (weight uint))
    (let
        (
            (total (var-get total-value-locked))
        )
        (if (is-eq total u0)
            u0
            (/ (* weight PRECISION-FACTOR) total)
        )
    )
)

;; public functions

;; Initialize a new yield strategy
(define-public (add-strategy 
    (name (string-ascii 50))
    (predicted-apy uint)
    (risk-score uint)
    (initial-weight uint))
    (let
        (
            (strategy-id (var-get strategy-count))
        )
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (< strategy-id MAX-STRATEGIES) ERR-NOT-AUTHORIZED)
        (asserts! (<= risk-score u100) ERR-INVALID-WEIGHT)
        (asserts! (> initial-weight u0) ERR-INVALID-WEIGHT)
        
        (map-set strategies strategy-id
            {
                name: name,
                apy-prediction: predicted-apy,
                risk-score: risk-score,
                ml-weight: initial-weight,
                performance-history: (list u0 u0 u0 u0 u0),
                total-allocated: u0,
                is-active: true,
                confidence-score: u50
            }
        )
        (var-set strategy-count (+ strategy-id u1))
        (ok strategy-id)
    )
)

;; User deposits funds into the optimizer
(define-public (deposit (amount uint))
    (let
        (
            (shares (calculate-shares amount))
            (current-deposit (default-to 
                {amount: u0, shares: u0, entry-block: u0, strategy-allocation: (list)}
                (map-get? user-deposits tx-sender)))
        )
        (asserts! (>= amount MIN-DEPOSIT) ERR-INVALID-AMOUNT)
        
        ;; Transfer STX to contract
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        ;; Update user position
        (map-set user-deposits tx-sender
            {
                amount: (+ (get amount current-deposit) amount),
                shares: (+ (get shares current-deposit) shares),
                entry-block: block-height,
                strategy-allocation: (list u0 u0 u0 u0 u0 u0 u0 u0 u0 u0)
            }
        )
        
        ;; Update global state
        (var-set total-value-locked (+ (var-get total-value-locked) amount))
        (var-set total-shares (+ (var-get total-shares) shares))
        
        (ok shares)
    )
)

;; Withdraw funds with earned yield
(define-public (withdraw (shares-to-burn uint))
    (let
        (
            (user-position (unwrap! (map-get? user-deposits tx-sender) ERR-INSUFFICIENT-BALANCE))
            (user-shares (get shares user-position))
            (tvl (var-get total-value-locked))
            (total-shares-supply (var-get total-shares))
            (withdrawal-amount (/ (* shares-to-burn tvl) total-shares-supply))
        )
        (asserts! (<= shares-to-burn user-shares) ERR-INSUFFICIENT-BALANCE)
        (asserts! (> withdrawal-amount u0) ERR-INVALID-AMOUNT)
        
        ;; Transfer STX back to user
        (try! (as-contract (stx-transfer? withdrawal-amount tx-sender tx-sender)))
        
        ;; Update user position
        (if (is-eq shares-to-burn user-shares)
            (map-delete user-deposits tx-sender)
            (map-set user-deposits tx-sender
                (merge user-position {
                    shares: (- user-shares shares-to-burn),
                    amount: (- (get amount user-position) withdrawal-amount)
                })
            )
        )
        
        ;; Update global state
        (var-set total-value-locked (- tvl withdrawal-amount))
        (var-set total-shares (- total-shares-supply shares-to-burn))
        
        (ok withdrawal-amount)
    )
)

;; ML-based strategy selection and rebalancing
(define-public (ml-rebalance-strategies)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        
        ;; Increment epoch for new learning cycle
        (var-set current-epoch (+ (var-get current-epoch) u1))
        
        ;; This would trigger reallocation based on updated ML weights
        ;; In production, this would redistribute TVL across strategies
        (ok true)
    )
)

;; Update performance metrics and retrain ML weights
(define-public (record-strategy-performance 
    (strategy-id uint)
    (actual-apy uint)
    (sharpe-ratio uint))
    (let
        (
            (strategy (unwrap! (map-get? strategies strategy-id) ERR-STRATEGY-NOT-FOUND))
            (predicted-apy (get apy-prediction strategy))
            (prediction-error (if (> actual-apy predicted-apy)
                                (- actual-apy predicted-apy)
                                (- predicted-apy actual-apy)))
            (performance-delta (if (> actual-apy predicted-apy) 
                                (to-int (- actual-apy predicted-apy))
                                (* -1 (to-int (- predicted-apy actual-apy)))))
            (epoch (var-get current-epoch))
        )
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        
        ;; Record performance metrics
        (map-set performance-metrics
            {strategy-id: strategy-id, epoch: epoch}
            {
                actual-apy: actual-apy,
                prediction-error: prediction-error,
                sharpe-ratio: sharpe-ratio,
                timestamp: block-height
            }
        )
        
        ;; Update ML weight based on performance
        (update-strategy-weight strategy-id performance-delta)
        
        ;; Update confidence score based on prediction accuracy
        (let
            (
                (accuracy (if (is-eq predicted-apy u0)
                            u50
                            (- u100 (/ (* prediction-error u100) predicted-apy))))
                (new-confidence (min-uint u100 (max-uint u10 accuracy)))
            )
            (map-set strategies strategy-id
                (merge strategy {
                    confidence-score: new-confidence,
                    apy-prediction: actual-apy ;; Update prediction with actual
                })
            )
        )
        
        (ok true)
    )
)

;; Advanced ML feature: Dynamic risk-adjusted portfolio optimization
;; This function implements a sophisticated allocation algorithm that combines
;; multiple ML concepts: risk scoring, confidence weighting, and momentum-based adjustments
(define-public (optimize-portfolio-allocation)
    (let
        (
            (tvl (var-get total-value-locked))
            (num-strategies (var-get strategy-count))
        )
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (> tvl u0) ERR-INVALID-AMOUNT)
        
        ;; Calculate optimal allocation using ML-weighted risk-adjusted returns
        (let
            (
                ;; Get all active strategies and calculate their scores
                (strategy-scores (calculate-all-strategy-scores num-strategies))
                (total-score (fold + strategy-scores u0))
            )
            
            ;; Allocate funds proportionally to ML-adjusted scores
            (if (> total-score u0)
                (begin
                    ;; Apply allocations to each strategy
                    (fold apply-strategy-allocation 
                        strategy-scores
                        {index: u0, total-score: total-score, tvl: tvl})
                    (ok true)
                )
                (ok false)
            )
        )
    )
)

;; Helper for portfolio optimization: Calculate scores for all strategies
(define-private (calculate-all-strategy-scores (count uint))
    (map calculate-strategy-score-by-index (list u0 u1 u2 u3 u4 u5 u6 u7 u8 u9))
)

(define-private (calculate-strategy-score-by-index (index uint))
    (let
        (
            (strategy-opt (map-get? strategies index))
        )
        (match strategy-opt
            strategy
                (if (get is-active strategy)
                    (let
                        (
                            (apy (get apy-prediction strategy))
                            (risk (get risk-score strategy))
                            (confidence (get confidence-score strategy))
                            (ml-weight (get ml-weight strategy))
                            (base-score (calculate-risk-adjusted-score apy risk confidence))
                        )
                        ;; Combine risk-adjusted score with ML weight
                        (/ (* base-score ml-weight) PRECISION-FACTOR)
                    )
                    u0
                )
            u0
        )
    )
)

;; Helper for portfolio optimization: Apply calculated allocation
(define-private (apply-strategy-allocation 
    (score uint)
    (state {index: uint, total-score: uint, tvl: uint}))
    (let
        (
            (index (get index state))
            (total-score (get total-score state))
            (tvl (get tvl state))
            (allocation (/ (* score tvl) total-score))
            (strategy-opt (map-get? strategies index))
        )
        (match strategy-opt
            strategy
                (begin
                    (map-set strategies index
                        (merge strategy {total-allocated: allocation})
                    )
                    {index: (+ index u1), total-score: total-score, tvl: tvl}
                )
            {index: (+ index u1), total-score: total-score, tvl: tvl}
        )
    )
)


