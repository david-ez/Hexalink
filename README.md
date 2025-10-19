# Hexalink Smart Contract

## Overview

Hexalink is a decentralized supply chain verification system built on the Stacks blockchain. It enables manufacturers, distributors, and retailers to immutably record and verify product movements, certifications, and ownership changes throughout the supply chain. Each transaction ensures transparency, traceability, and authenticity verification.

## Features

* **Item Registration**: Producers can register new items with detailed metadata including category, lot number, and origin.
* **Waypoints Tracking**: Tracks each logistical step such as manufacturing, shipping, customs, warehousing, and retail.
* **Authorized Validators**: Organizations can designate validators authorized to confirm checkpoints and compliance.
* **Ownership Transfers**: Handles item handovers between entities with recordable acceptance, rejection, and cancellation.
* **Compliance Records**: Supports certification and compliance documentation for regulatory tracking and auditing.
* **Item Recall Mechanism**: Allows producers to issue product recalls with verifiable reasons.
* **Authenticity Verification**: Read-only functions provide item state and authenticity status for consumers or partners.

## Core Data Structures

* `inventory-items`: Stores item metadata, source, holder, and status.
* `waypoints`: Records item movements with timestamp, handler, and proof hashes.
* `organization-validators`: Manages authorized verifiers per organization.
* `ownership-transfers`: Tracks ownership change events and outcomes.
* `compliance-records`: Records certifications with validity, expiry, and proof documents.

## Key Functions

### Public

* `register-item`: Registers a new product in the supply chain.
* `add-waypoint`: Adds a new location or process checkpoint.
* `authorize-validator` and `revoke-validator`: Manage organization validators.
* `initiate-handover`, `accept-handover`, `reject-handover`, `cancel-handover`: Handle item transfers.
* `add-compliance-record` and `revoke-compliance-record`: Manage certification lifecycle.
* `recall-item`: Marks an item as recalled and logs the reason.
* `set-delivery-details`: Updates delivery targets and expected timelines.

### Read-Only

* `get-item-details`, `get-waypoint`, `get-handover`, `get-compliance-record`: Retrieve stored records.
* `is-compliance-record-valid`: Validates the current status of compliance records.
* `verify-item-authenticity`: Confirms item existence and producer authenticity.

## Error Handling

All critical operations include validation checks for:

* Unauthorized access or invalid actors.
* Nonexistent items or records.
* Improper handover or compliance states.
* Attempted updates on recalled items.

## Usage

Deployed participants (producers, validators, carriers, retailers) interact with Hexalink to:

1. Register items.
2. Log supply chain events.
3. Certify compliance.
4. Transfer and verify ownership.
5. Audit authenticity in real-time via read-only calls.

This structure ensures end-to-end visibility, accountability, and trust in every stage of the product journey.
