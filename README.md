# bit-market

**Bit-Market** is a complex, fully autonomous retail simulation ecosystem featuring distinct AI lifeforms, dynamic environmental interactions, and a "Toy-Store" visual style.

## 🛒 Overview

The simulation renders entirely inside an HTML5 Canvas and runs at 60 fps without any build step.  Open `index.html` in a browser (or `npm start`) to watch the ecosystem come to life.

### AI Lifeforms

| Entity | Role | States |
|--------|------|--------|
| 🛍️ **Shopper** | Autonomous customer | `ENTERING` → `BROWSING` → `MOVING_TO_SHELF` → `SHOPPING` → `MOVING_TO_CHECKOUT` → `QUEUING` → `CHECKING_OUT` → `LEAVING` |
| 🤖 **StoreBot** | Restocking robot | `IDLE` → `SCANNING` → `MOVING_TO_WAREHOUSE` → `LOADING` → `MOVING_TO_SHELF` → `RESTOCKING` |
| 👤 **Clerk** | Checkout operator | `IDLE` → `BECKONING` → `SERVING` |

**Shopper archetypes** – four distinct personalities (Impulsive, Budget, Explorer, Rushed) each with unique speeds, budgets and shopping-list sizes.

### Dynamic Environmental Interactions

* **Supply–demand pricing** – product prices rise automatically when stock is low.
* **Autonomous restocking** – StoreBots scan for under-stocked shelves, fetch goods from the warehouse and restock in real time.
* **Queue management** – shoppers always join the shortest checkout queue; clerks serve them in order.
* **Happiness tracking** – shoppers lose happiness when shelves are empty or items are out of budget, gaining it back on successful purchases.

### Visual Style

Bright candy colours, rounded corners, animated conveyor belts, emoji product icons and a checkered toy-store floor create the playful "Toy-Store" aesthetic.

## 🗂️ Project Structure

```
bit-market/
├── index.html                  # Main entry point – open in any browser
├── src/
│   ├── main.js                 # Wires canvas + Simulation + Renderer
│   ├── Simulation.js           # Core autonomous loop
│   ├── entities/
│   │   ├── Entity.js           # Base AI lifeform class
│   │   ├── Shopper.js          # Customer AI
│   │   ├── StoreBot.js         # Restocking robot AI
│   │   └── Clerk.js            # Checkout clerk AI
│   ├── environment/
│   │   ├── Store.js            # Store layout & environment
│   │   ├── Shelf.js            # Shelf with stock management
│   │   ├── Product.js          # Product catalogue & dynamic pricing
│   │   └── Checkout.js         # Checkout counter & queue
│   ├── ai/
│   │   └── StateMachine.js     # Generic finite-state machine
│   └── renderer/
│       ├── Renderer.js         # HTML5 Canvas renderer
│       └── colors.js           # Toy-store colour palette
└── tests/
    ├── Simulation.test.js
    ├── entities/
    │   ├── Entity.test.js
    │   ├── Shopper.test.js
    │   └── StoreBot.test.js
    └── environment/
        ├── Product.test.js
        ├── Shelf.test.js
        └── Store.test.js
```

## 🚀 Getting Started

```bash
# Install dev dependencies (Jest for testing)
npm install

# Run the simulation (requires Node ≥ 18 for npx serve)
npm start          # then open http://localhost:3000

# Or simply open index.html directly in a browser

# Run all tests
npm test
```

## 🧪 Tests

46 unit tests covering all core classes:

```
npm test
```
