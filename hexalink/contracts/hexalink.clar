;; Supply Chain Verification System
;; Enables tracking of products through the supply chain with
;; immutable records and verification at each step of the process

;; Item definitions
(define-map product-registry
  { product-id: uint }
  {
    product-name: (string-utf8 128),
    product-description: (string-utf8 1024),
    manufacturer: principal,
    batch-number: (string-ascii 64),
    registered-at: uint,
    status: (string-ascii 32),  ;; "created", "in-transit", "delivered", "sold", "recalled"
    product-type: (string-ascii 64),
    origin-location: (string-utf8 128),
    current-owner: principal,
    delivery-location: (optional (string-utf8 128)),
    expected-delivery-block: (optional uint),
    product-uri: (optional (string-utf8 256))
  }
)

;; Supply chain waypoints
(define-map checkpoints
  { product-id: uint, checkpoint-id: uint }
  {
    location: (string-utf8 128),
    timestamp: uint,
    operator: principal,
    verified-by: principal,
    checkpoint-type: (string-ascii 32),  ;; "manufacture", "shipping", "customs", "warehouse", "retail", "delivery"
    temperature: (optional int),         ;; For temperature-sensitive goods
    humidity: (optional uint),           ;; For humidity-sensitive goods
    notes: (optional (string-utf8 512)),
    attestation-hash: (buff 32)         ;; Hash of checkpoint attestation document
  }
)

;; Authorized validators for each company
(define-map authorized-verifiers
  { organization: principal, verifier: principal }
  {
    verifier-name: (string-utf8 128),
    role: (string-ascii 64),
    authorized-at: uint,
    authorized-by: principal,
    is-active: bool
  }
)

;; Ownership transfers
(define-map transfer-records
  { product-id: uint, transfer-id: uint }
  {
    transferor: principal,
    transferee: principal,
    initiated-at: uint,
    completed-at: (optional uint),
    transfer-status: (string-ascii 32),  ;; "pending", "completed", "rejected", "cancelled"
    conditions: (optional (string-utf8 512))
  }
)

;; Certifications and compliance
(define-map certification-registry
  { product-id: uint, certification-type: (string-ascii 64) }
  {
    certifier: principal,
    issued-at: uint,
    expiration-block: uint,
    cert-hash: (buff 32),
    cert-uri: (optional (string-utf8 256)),
    cert-status: (string-ascii 32)  ;; "valid", "expired", "revoked"
  }
)

;; Next available IDs
(define-data-var next-product-id uint u0)
(define-map next-checkpoint-id { product-id: uint } { id: uint })
(define-map next-transfer-id { product-id: uint } { id: uint })

;; Helper function to convert string to buffer for hashing
(define-private (encode-utf8-buffer (input (string-utf8 512)))
  ;; In a real implementation, you would convert the string to bytes
  0x68656c6c6f20776f726c64 ;; Example buffer (represents "hello world" in hex)
)

;; Helper function to convert ascii string to buffer for hashing
(define-private (encode-ascii-buffer (input (string-ascii 64)))
  ;; In a real implementation, you would convert the string to bytes
  0x68656c6c6f20776f726c64 ;; Example buffer (represents "hello world" in hex)
)

;; Helper function to convert principal to string
(define-private (principal-to-string (input principal))
  u"principal" ;; Simplified implementation
)

;; Register a new item
(define-public (register-product
                (product-name (string-utf8 128))
                (product-description (string-utf8 1024))
                (batch-number (string-ascii 64))
                (product-type (string-ascii 64))
                (origin-location (string-utf8 128))
                (product-uri (optional (string-utf8 256))))
  (let
    ((product-id (var-get next-product-id)))
    
    ;; Create the item record
    (map-set product-registry
      { product-id: product-id }
      {
        product-name: product-name,
        product-description: product-description,
        manufacturer: tx-sender,
        batch-number: batch-number,
        registered-at: block-height,
        status: "created",
        product-type: product-type,
        origin-location: origin-location,
        current-owner: tx-sender,
        delivery-location: none,
        expected-delivery-block: none,
        product-uri: product-uri
      }
    )
    
    ;; Initialize waypoint counter
    (map-set next-checkpoint-id
      { product-id: product-id }
      { id: u0 }
    )
    
    ;; Initialize handover counter
    (map-set next-transfer-id
      { product-id: product-id }
      { id: u0 }
    )
    
    ;; Create initial manufacturing waypoint
    (try! (add-checkpoint
            product-id
            origin-location
            "manufacture"
            none
            none
            (some u"Item manufactured with lot number")
            (sha256 (encode-ascii-buffer batch-number))
          ))
    
    ;; Increment item ID counter
    (var-set next-product-id (+ product-id u1))
    
    (ok product-id)
  )
)

;; Add a waypoint to an item's supply chain journey
(define-public (add-checkpoint
                (product-id uint)
                (location (string-utf8 128))
                (checkpoint-type (string-ascii 32))
                (temperature (optional int))
                (humidity (optional uint))
                (notes (optional (string-utf8 512)))
                (attestation-hash (buff 32)))
  (let
    ((product (unwrap! (map-get? product-registry { product-id: product-id }) (err u"Item not found")))
     (checkpoint-counter (unwrap! (map-get? next-checkpoint-id { product-id: product-id }) 
                                 (err u"Counter not found")))
     (checkpoint-id (get id checkpoint-counter)))
    
    ;; Validate
    (asserts! (or (is-eq tx-sender (get current-owner product)) 
                  (is-authorized-verifier (get current-owner product) tx-sender))
              (err u"Not authorized to add waypoint"))
    (asserts! (not (is-eq (get status product) "recalled")) (err u"Item has been recalled"))
    
    ;; Create the waypoint
    (map-set checkpoints
      { product-id: product-id, checkpoint-id: checkpoint-id }
      {
        location: location,
        timestamp: block-height,
        operator: (get current-owner product),
        verified-by: tx-sender,
        checkpoint-type: checkpoint-type,
        temperature: temperature,
        humidity: humidity,
        notes: notes,
        attestation-hash: attestation-hash
      }
    )
    
    ;; Update item state based on waypoint category
    (map-set product-registry
      { product-id: product-id }
      (merge product 
        { 
          status: (if (is-eq checkpoint-type "delivery") "delivered" 
                    (if (is-eq checkpoint-type "retail-sale") "sold" "in-transit"))
        }
      )
    )
    
    ;; Increment waypoint counter
    (map-set next-checkpoint-id
      { product-id: product-id }
      { id: (+ checkpoint-id u1) }
    )
    
    (ok checkpoint-id)
  )
)

;; Check if a principal is an authorized validator for an organization
(define-private (is-authorized-verifier (organization principal) (verifier principal))
  (match (map-get? authorized-verifiers { organization: organization, verifier: verifier })
    verifier-info (get is-active verifier-info)
    false
  )
)

;; Authorize a validator for an organization
(define-public (authorize-verifier
                (verifier principal)
                (verifier-name (string-utf8 128))
                (role (string-ascii 64)))
  (begin
    ;; Set validator as authorized
    (map-set authorized-verifiers
      { organization: tx-sender, verifier: verifier }
      {
        verifier-name: verifier-name,
        role: role,
        authorized-at: block-height,
        authorized-by: tx-sender,
        is-active: true
      }
    )
    
    (ok true)
  )
)

;; Revoke a validator's authorization
(define-public (revoke-verifier (verifier principal))
  (let
    ((verifier-info (unwrap! (map-get? authorized-verifiers { organization: tx-sender, verifier: verifier })
                            (err u"Validator not found"))))
    
    (map-set authorized-verifiers
      { organization: tx-sender, verifier: verifier }
      (merge verifier-info { is-active: false })
    )
    
    (ok true)
  )
)

;; Initiate ownership handover of an item
(define-public (initiate-transfer
                (product-id uint)
                (transferee principal)
                (conditions (optional (string-utf8 512))))
  (let
    ((product (unwrap! (map-get? product-registry { product-id: product-id }) (err u"Item not found")))
     (transfer-counter (unwrap! (map-get? next-transfer-id { product-id: product-id }) 
                               (err u"Counter not found")))
     (transfer-id (get id transfer-counter)))
    
    ;; Validate
    (asserts! (is-eq tx-sender (get current-owner product)) 
              (err u"Only current holder can initiate handover"))
    (asserts! (not (is-eq (get status product) "recalled")) 
              (err u"Item has been recalled"))
    
    ;; Create handover record
    (map-set transfer-records
      { product-id: product-id, transfer-id: transfer-id }
      {
        transferor: tx-sender,
        transferee: transferee,
        initiated-at: block-height,
        completed-at: none,
        transfer-status: "pending",
        conditions: conditions
      }
    )
    
    ;; Increment handover counter
    (map-set next-transfer-id
      { product-id: product-id }
      { id: (+ transfer-id u1) }
    )
    
    (ok transfer-id)
  )
)

;; Accept an ownership handover
(define-public (accept-transfer (product-id uint) (transfer-id uint))
  (let
    ((product (unwrap! (map-get? product-registry { product-id: product-id }) (err u"Item not found")))
     (transfer (unwrap! (map-get? transfer-records { product-id: product-id, transfer-id: transfer-id })
                       (err u"Handover not found"))))
    
    ;; Validate
    (asserts! (is-eq tx-sender (get transferee transfer)) (err u"Only receiver can accept"))
    (asserts! (is-eq (get transfer-status transfer) "pending") (err u"Handover not pending"))
    
    ;; Update handover record
    (map-set transfer-records
      { product-id: product-id, transfer-id: transfer-id }
      (merge transfer 
        { 
          completed-at: (some block-height),
          transfer-status: "completed"
        }
      )
    )
    
    ;; Update item holder
    (map-set product-registry
      { product-id: product-id }
      (merge product { current-owner: tx-sender })
    )
    
    ;; Add a waypoint for the ownership handover
    (try! (add-checkpoint
            product-id
            u"ownership-handover" ;; Generic location for handover as utf8
            "transfer"
            none
            none
            (some u"Ownership transferred")
            (sha256 (encode-utf8-buffer u"ownership-handover"))
          ))
    
    (ok true)
  )
)

;; Reject an ownership handover
(define-public (reject-transfer (product-id uint) (transfer-id uint) (reason (string-utf8 512)))
  (let
    ((transfer (unwrap! (map-get? transfer-records { product-id: product-id, transfer-id: transfer-id })
                       (err u"Handover not found"))))
    
    ;; Validate
    (asserts! (is-eq tx-sender (get transferee transfer)) (err u"Only receiver can reject"))
    (asserts! (is-eq (get transfer-status transfer) "pending") (err u"Handover not pending"))
    
    ;; Update handover record
    (map-set transfer-records
      { product-id: product-id, transfer-id: transfer-id }
      (merge transfer 
        { 
          completed-at: (some block-height),
          transfer-status: "rejected",
          conditions: (some reason)
        }
      )
    )
    
    (ok true)
  )
)

;; Cancel a pending handover (only current holder)
(define-public (cancel-transfer (product-id uint) (transfer-id uint))
  (let
    ((transfer (unwrap! (map-get? transfer-records { product-id: product-id, transfer-id: transfer-id })
                       (err u"Handover not found"))))
    
    ;; Validate
    (asserts! (is-eq tx-sender (get transferor transfer)) (err u"Only sender can cancel"))
    (asserts! (is-eq (get transfer-status transfer) "pending") (err u"Handover not pending"))
    
    ;; Update handover record
    (map-set transfer-records
      { product-id: product-id, transfer-id: transfer-id }
      (merge transfer 
        { 
          completed-at: (some block-height),
          transfer-status: "cancelled"
        }
      )
    )
    
    (ok true)
  )
)

;; Add compliance record to an item
(define-public (add-certification
                (product-id uint)
                (certification-type (string-ascii 64))
                (expiration-block uint)
                (cert-hash (buff 32))
                (cert-uri (optional (string-utf8 256))))
  (let
    ((product (unwrap! (map-get? product-registry { product-id: product-id }) (err u"Item not found"))))
    
    ;; Validate
    (asserts! (or (is-eq tx-sender (get manufacturer product)) 
                  (is-authorized-verifier (get manufacturer product) tx-sender))
              (err u"Not authorized to add compliance record"))
    (asserts! (> expiration-block block-height) (err u"Compliance record must be valid for future blocks"))
    
    ;; Add compliance record
    (map-set certification-registry
      { product-id: product-id, certification-type: certification-type }
      {
        certifier: tx-sender,
        issued-at: block-height,
        expiration-block: expiration-block,
        cert-hash: cert-hash,
        cert-uri: cert-uri,
        cert-status: "valid"
      }
    )
    
    (ok true)
  )
)

;; Revoke a compliance record
(define-public (revoke-certification (product-id uint) (certification-type (string-ascii 64)))
  (let
    ((compliance-record (unwrap! (map-get? certification-registry 
                               { product-id: product-id, certification-type: certification-type })
                             (err u"Compliance record not found"))))
    
    ;; Validate
    (asserts! (is-eq tx-sender (get certifier compliance-record)) 
              (err u"Only authority can revoke compliance record"))
    
    ;; Update compliance record
    (map-set certification-registry
      { product-id: product-id, certification-type: certification-type }
      (merge compliance-record { cert-status: "revoked" })
    )
    
    (ok true)
  )
)

;; Issue an item recall
(define-public (recall-product (product-id uint) (reason (string-utf8 512)))
  (let
    ((product (unwrap! (map-get? product-registry { product-id: product-id }) (err u"Item not found"))))
    
    ;; Validate
    (asserts! (is-eq tx-sender (get manufacturer product)) 
              (err u"Only producer can recall item"))
    
    ;; Update item state
    (map-set product-registry
      { product-id: product-id }
      (merge product { status: "recalled" })
    )
    
    ;; Add a waypoint for the recall
    (try! (add-checkpoint
            product-id
            u"recall" ;; Using utf8 string for position
            "recall"
            none
            none
            (some reason)
            (sha256 (encode-utf8-buffer reason))
          ))
    
    (ok true)
  )
)

;; Set target destination and anticipated delivery
(define-public (set-delivery-info
                (product-id uint)
                (delivery-location (string-utf8 128))
                (expected-delivery-block uint))
  (let
    ((product (unwrap! (map-get? product-registry { product-id: product-id }) (err u"Item not found"))))
    
    ;; Validate
    (asserts! (or (is-eq tx-sender (get current-owner product)) 
                  (is-authorized-verifier (get current-owner product) tx-sender))
              (err u"Not authorized to set delivery details"))
    
    ;; Update item
    (map-set product-registry
      { product-id: product-id }
      (merge product 
        { 
          delivery-location: (some delivery-location),
          expected-delivery-block: (some expected-delivery-block)
        }
      )
    )
    
    (ok true)
  )
)

;; Read-only functions

;; Get item details
(define-read-only (get-product-details (product-id uint))
  (ok (unwrap! (map-get? product-registry { product-id: product-id }) (err u"Item not found")))
)

;; Get waypoint details
(define-read-only (get-checkpoint (product-id uint) (checkpoint-id uint))
  (ok (unwrap! (map-get? checkpoints { product-id: product-id, checkpoint-id: checkpoint-id })
              (err u"Waypoint not found")))
)

;; Get handover details
(define-read-only (get-transfer (product-id uint) (transfer-id uint))
  (ok (unwrap! (map-get? transfer-records { product-id: product-id, transfer-id: transfer-id })
              (err u"Handover not found")))
)

;; Get compliance record details
(define-read-only (get-certification (product-id uint) (certification-type (string-ascii 64)))
  (ok (unwrap! (map-get? certification-registry { product-id: product-id, certification-type: certification-type })
              (err u"Compliance record not found")))
)

;; Check if compliance record is valid
(define-read-only (is-certification-valid (product-id uint) (certification-type (string-ascii 64)))
  (match (map-get? certification-registry { product-id: product-id, certification-type: certification-type })
    compliance-record (and (is-eq (get cert-status compliance-record) "valid")
                       (> (get expiration-block compliance-record) block-height))
    false
  )
)

;; Verify item authenticity (basic check)
(define-read-only (verify-product-authenticity (product-id uint))
  (match (map-get? product-registry { product-id: product-id })
    product (ok {
              authentic: true,
              manufacturer: (get manufacturer product),
              batch-number: (get batch-number product),
              status: (get status product)
            })
    (err u"Item not found")
  )
)