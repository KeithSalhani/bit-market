
## Summary
The Bit-Market is a complex, fully autonomous retail simulation ecosystem featuring distinct AI lifeforms, dynamic environmental interactions, and a polished, "Toy-Store" visual style. The project demonstrates advanced multi-agent interaction and technical complexity, utilizing a combination of sophisticated algorithms and a clean, decoupled system architecture

![](https://i.imgur.com/3c8cGtw.jpeg)

## 1. Identity & Personality
**The Lifeforms:**
*   **"Bits" (The Shoppers):** Small, round, hover-bots with expressive digital eyes (LED-style displays) and "floating" procedural hands. They possess individual traits:
    *   **Hurry-Bot:** Moves at high velocity, gets frustrated (red eyes) if the checkout line is too long.
    *   **Browser-Bot:** Distracted by "sale" signs, moves in erratic patterns, and chirps happily (green eyes) when finding items.
    *   **Grumpy-Bot:** Emits low-frequency beeps and "glares" at other shoppers who block its path.
*   **"Clicks" (The Cashiers):** Stationary but highly responsive AIs attached to checkout counters. Their "heads" (monitors) track the Shoppers' movements using a look-at constraint, and they change their facial expressions based on transaction speed.

## 2. Groovyness 
*   **Aesthetic:** A vibrant "Grocery-Store" visual style.
*   **Visual Effects:**
    *   **Scanning Beam:** A procedural laser shader for the Cashier's scanner that reacts to item collision.
    *   **Mood Particles:** Floating emoji-style particles (hearts for success, storm clouds for frustration) that spawn above the AIs.
    *   **Possibly Mesh Deformations:** "Squash and stretch" on the Bits' bodies when they hover-jump to reach high shelves.
*   **Sound Design:** Procedural "chatter" (high-pitched sine-wave beeps) that shifts pitch and tempo based on the AI's happiness state. Spatial audio for environmental interactions (clinking items, humming refrigerators).

## 3. Complexity
*   **Brain Architecture:**
    *   **Behavior Tree (BT):** Each Shopper uses a BT to manage high-level goals: `FindItem` -> `SteerToShelf` -> `ReachForItem` (IK) -> `QueueAtCheckout`.
    *   **Finite State Machine (FSM):** The Cashiers use an FSM to manage the checkout lifecycle: `Idle` -> `Scanning` -> `ProcessingPayment` -> `ThankingShopper`.
*   **Movement & Math:**
    *   **Steering Behaviors:** Implements **Seek** (for items), **Arrive** (at counters), and **Obstacle Avoidance** (to navigate around the player and other bots).
    *   **Flocking:** Uses a "separation" force to prevent bots from clumping in narrow aisles.
    *   **Inverse Kinematics (IK):** Floating hands use IK to grab physics-enabled items from varying shelf heights and place them into a moving cart.
*   **Inter-Agent Communication:** A custom `TransactionInterface` allows Shoppers and Cashiers to exchange data (item IDs, price, satisfaction levels) during the checkout phase.

## 4. Player Interaction
*   **Environmental Manipulation:** The player can physically move items, block aisles with "Wet Floor" signs.

*   **Autonomous Reaction:** The AIs perceive player interference as an environmental obstacle. A Bit might "cry" or fight if the player steals an item from its cart, or "celebrate" if the player helps it reach a high shelf.

## 5. System Architecture
*   `ShopperController`: The main node managing the Behavior Tree and state.
*   `SteeringVehicle`: A decoupled class for handling all physics-based movement forces.
*   `IKHandSystem`: Manages the procedural arm/hand movement independently of the body.
*   `MarketRegistry`: A singleton tracking item locations and checkout queue lengths.
*   `EmotionEngine`: A component that calculates "Mood" based on external triggers and updates shaders/sounds.
*   `ItemResource`: A data-driven approach to item properties (metadata, price, weight).

