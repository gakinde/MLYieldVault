MLYieldVault
============

* * * * *

🚀 Overview: ML-Enhanced Yield Optimizer
----------------------------------------

The `MLYieldVault` is an advanced Stacks smart contract designed to operate as a **DeFi Yield Optimizer**. What sets it apart is the integration of **Machine Learning (ML)-inspired mechanisms** for dynamic strategy selection and capital allocation.

Instead of relying on static rules or governance votes for rebalancing, this vault uses quantitative metrics like **Predicted APY**, **Risk Score**, and an **ML Weight** that adjusts based on historical performance. This creates a self-optimizing system intended to maximize risk-adjusted returns for depositors.

The contract manages staked STX (or a similar token) and calculates a fungible share token for users, reflecting their proportional ownership of the vault's total value locked (TVL), including accrued yield.

* * * * *

✨ Key Features
--------------

-   **ML-Inspired Strategy Scoring:** Strategies are scored using a formula that combines:

    -   **Predicted APY**

    -   **Risk Score** (a penalty for risk)

    -   **ML Confidence Score** (a boost for high confidence)

    -   **ML Weight** (dynamically adjusted based on past performance).

-   **Dynamic Weight Adjustment:** The `update-strategy-weight` private function implements a simplified, learning-rate-adjusted mechanism (akin to gradient descent) to increase the weight of high-performing strategies and decrease the weight of underperforming ones.

-   **Share-Based Accounting:** Deposits and withdrawals utilize the standard yield aggregator model: users receive shares proportional to the current TVL, allowing the vault to track and distribute yield seamlessly.

-   **Portfolio Rebalancing:** The `optimize-portfolio-allocation` public function allows the contract owner to rebalance the vault's capital across the best-performing, risk-adjusted strategies.

-   **Historical Performance Tracking:** The `performance-metrics` map tracks **Actual APY**, **Prediction Error**, and **Sharpe Ratio** over epochs, providing data for the system's "learning."

-   **Precision Handling:** Utilizes a `PRECISION-FACTOR` of $\text{u}1000000$ (6 decimals) for accurate financial and ML-related calculations.

* * * * *

🛠️ Contract Architecture & Data Structures
-------------------------------------------

### Constants

| **Constant** | **Value** | **Description** |
| --- | --- | --- |
| `CONTRACT-OWNER` | `tx-sender` | Address allowed to execute administrative functions (rebalance, add strategy, record performance). |
| `MAX-STRATEGIES` | `u10` | Hard limit on the number of supported DeFi strategies. |
| `PRECISION-FACTOR` | `u1000000` | Used to scale percentage and decimal values for integer arithmetic (6 decimal places). |
| `MIN-DEPOSIT` | `u1000000` | Minimum deposit amount, equivalent to 1 STX (assuming 6 decimals). |

### Data Variables

| **Variable** | **Type** | **Description** |
| --- | --- | --- |
| `total-value-locked` | `uint` | The total value of assets managed by the vault. |
| `strategy-count` | `uint` | The current number of registered strategies. |
| `ml-learning-rate` | `uint` | The factor determining how quickly ML weights adjust after performance updates (initial $\text{u}50 \rightarrow 0.00005$). |
| `current-epoch` | `uint` | Tracks the current training/rebalancing cycle for the ML component. |
| `total-shares` | `uint` | The total supply of vault shares outstanding. |

### Data Maps

| **Map Name** | **Key Type** | **Value Type** | **Description** |
| --- | --- | --- | --- |
| `user-deposits` | `principal` | `{amount: uint, shares: uint, ...}` | Tracks a user's total principal, earned shares, entry block, and historical strategy allocation. |
| `strategies` | `uint` (Strategy ID) | `{name: (string-ascii 50), apy-prediction: uint, risk-score: uint, ml-weight: uint, ...}` | Stores the configuration and dynamic ML parameters for each yield strategy. |
| `performance-metrics` | `{strategy-id: uint, epoch: uint}` | `{actual-apy: uint, prediction-error: uint, ...}` | Historical record used to evaluate and train the ML component over time. |

* * * * *

🔑 Public Functions (API)
-------------------------

### `(add-strategy (name (string-ascii 50)) (predicted-apy uint) (risk-score uint) (initial-weight uint))`

-   **Description:** Allows the `CONTRACT-OWNER` to register a new yield strategy with initial ML parameters.

-   **Authorisation:** Only callable by the `CONTRACT-OWNER`.

-   **Pre-conditions:** `strategy-count` must be less than `MAX-STRATEGIES`. `risk-score` $\le \text{u}100$. `initial-weight` $ > \text{u}0$.

-   **Returns:** `(ok strategy-id)` on success, or an error.

### `(deposit (amount uint))`

-   **Description:** Transfers STX from the sender to the contract and mints vault shares proportional to the current TVL.

-   **Pre-conditions:** `amount` must be $\ge \text{MIN-DEPOSIT}$.

-   **Logic:**

    1.  Calculates new shares using `(calculate-shares amount)`.

    2.  Transfers STX into the contract.

    3.  Updates `user-deposits` and global `total-value-locked` and `total-shares`.

-   **Returns:** `(ok shares)` minted on success, or an error.

### `(withdraw (shares-to-burn uint))`

-   **Description:** Redeems vault shares for the underlying asset (STX), including any accrued yield.

-   **Pre-conditions:** `shares-to-burn` must be less than or equal to the user's total shares.

-   **Logic:**

    1.  Calculates the proportional `withdrawal-amount` based on current `tvl` and `total-shares-supply`.

    2.  Transfers STX out of the contract to the user.

    3.  Updates `user-deposits`, `total-value-locked`, and `total-shares`.

-   **Returns:** `(ok withdrawal-amount)` on success, or an error.

### `(ml-rebalance-strategies)`

-   **Description:** Increments the `current-epoch`. This is a placeholder function that, in a full deployment, would initiate the actual fund reallocation process across integrated strategies based on the newly calculated ML weights.

-   **Authorisation:** Only callable by the `CONTRACT-OWNER`.

-   **Returns:** `(ok true)`.

### `(record-strategy-performance (strategy-id uint) (actual-apy uint) (sharpe-ratio uint))`

-   **Description:** Used by the `CONTRACT-OWNER` (or an oracle/off-chain ML service) to provide real-world performance data for a strategy. This function is the core of the "learning" process.

-   **Authorisation:** Only callable by the `CONTRACT-OWNER`.

-   **Logic:**

    1.  Calculates the `prediction-error` between `actual-apy` and `apy-prediction`.

    2.  Records the metrics in `performance-metrics`.

    3.  Calls the private `(update-strategy-weight)` function to adjust the ML weight based on the `performance-delta` (positive for outperformance, negative for underperformance).

    4.  Updates the strategy's `confidence-score` and sets the `apy-prediction` to the most recent `actual-apy`.

-   **Returns:** `(ok true)` on success, or an error.

### `(optimize-portfolio-allocation)`

-   **Description:** Executes the dynamic risk-adjusted portfolio optimization algorithm. This function calculates the optimal proportional allocation for all active strategies and updates the `total-allocated` field for each.

-   **Authorisation:** Only callable by the `CONTRACT-OWNER`.

-   **Logic:**

    1.  Uses `(calculate-all-strategy-scores)` to get a risk-adjusted, ML-weighted score for every active strategy.

    2.  Allocates the total `tvl` proportionally to these scores.

    3.  Updates the `total-allocated` field in the `strategies` map.

-   **Returns:** `(ok true)` if allocation is performed, `(ok false)` if total score is zero, or an error.

* * * * *

⚙️ Private Functions (Core Logic)
---------------------------------

| **Function** | **Purpose** |
| --- | --- |
| `(calculate-shares)` | Determines the number of vault shares to mint for a new deposit, accounting for existing TVL and total shares. |
| `(update-strategy-weight)` | **ML Training:** Adjusts the `ml-weight` for a strategy up or down based on its performance relative to its prediction, using a hardcoded learning rate. |
| `(calculate-risk-adjusted-score)` | **ML Scoring:** Computes a core return score by taking the `apy` and penalizing it by the `risk` score, then boosting it by the `confidence` score. |
| `(normalize-weights)` | A placeholder for a potential softmax-inspired function, intended to normalize a list of weights to sum to a target value (currently uses TVL for normalization in `normalize-single-weight`). |
| `(calculate-all-strategy-scores)` | Iterates through strategies to gather their ML-weighted risk-adjusted scores for portfolio optimization. |
| `(calculate-strategy-score-by-index)` | Calculates the final score for a single strategy by multiplying the `base-score` (risk-adjusted) by the `ml-weight`. |
| `(apply-strategy-allocation)` | Uses the final calculated score to determine and update the new `total-allocated` amount for a strategy. |

* * * * *

⚖️ License
----------

The `MLYieldVault` contract is released under the **MIT License**.

### MIT License

Copyright (c) 2025 MLYieldVault

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

* * * * *

🤝 Contribution
---------------

Contributions, issues, and feature requests are welcome! Feel free to check the [issues page] (if this were a real repository).

### Setup

To set up the development environment (using Clarinet or similar tools):

1.  Clone the repository:

    Bash

    ```
    git clone [repository-url]
    cd MLYieldVault

    ```

2.  Install dependencies (e.g., Clarinet):

    Bash

    ```
    # Assuming Clarinet is installed
    clarinet check

    ```

3.  Run tests:

    Bash

    ```
    clarinet test

    ```

### Reporting Bugs

If you find a bug or have a suggestion, please open an issue with the label "bug" or "enhancement."

* * * * *

⚠️ Disclaimer
-------------

This contract contains simplified, illustrative logic for **ML-inspired** strategy selection. It is a proof-of-concept for how machine learning data (e.g., predicted APY, confidence) can be used for on-chain decision-making. **The actual ML model training and data integrity are assumed to be handled by a secure, off-chain oracle or trusted external entity** that calls the `record-strategy-performance` function.

**Do not use this contract in a production environment without rigorous security audits, formal verification, and a robust oracle system for the ML inputs.**
