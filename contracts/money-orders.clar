;; An example contract that leverages signed structured data to trigger actions.
;; In this case, the contract-owner can sign "money orders", which are tuples containing
;; an amount, a recipient, and a salt. Signed money orders may be submitted to the contract
;; by anyone and will trigger an STX transfer from the contract to the recipient of the
;; money order if the signature is valid and that specific money order has not been seen
;; before. The salt is to guarantee uniqueness and should not be repeated.
;; What makes it fun is that these money orders can be generated by a device that never
;; connects to the internet. One also does not need to worry about transaction nonces.
;; As an added bonus, money orders can be cancelled by the contract-owner for as long
;; as they are not executed.

;; By Marvin Janssen

(define-constant contract-owner tx-sender)

(define-constant err-not-owner (err u100))
(define-constant err-invalid-signature (err u101))
(define-constant err-already-executed (err u102))

(define-constant chain-id u1)
(define-constant structured-data-prefix 0x534950303138)

(define-constant message-domain-hash (sha256 (to-consensus-buff
	{
		name: "Money Orders",
		version: "1.0.0",
		chain-id: chain-id
	}
)))

(define-constant structured-data-header (concat structured-data-prefix message-domain-hash))

(define-map money-orders {amount: uint, recipient: principal, salt: uint} uint)

(define-read-only (verify-signature (hash (buff 32)) (signature (buff 65)) (signer principal))
	(is-eq (principal-of? (unwrap! (secp256k1-recover? hash signature) false)) (ok signer))
)

(define-read-only (verify-signed-structured-data (structured-data-hash (buff 32)) (signature (buff 65)) (signer principal))
	(verify-signature (sha256 (concat structured-data-header structured-data-hash)) signature signer)
)

(define-read-only (executed-at (order {amount: uint, recipient: principal, salt: uint}))
	(map-get? money-orders order)
)

(define-public (execute-money-order (order {amount: uint, recipient: principal, salt: uint}) (signature (buff 65)))
	(begin
		(asserts! (is-none (executed-at order)) err-already-executed)
		(asserts! (verify-signed-structured-data (sha256 (to-consensus-buff order)) signature contract-owner) err-invalid-signature)
		(map-set money-orders order block-height)
		(as-contract (stx-transfer? (get amount order) tx-sender (get recipient order)))
	)
)

(define-public (cancel-money-order (order {amount: uint, recipient: principal, salt: uint}))
	(begin
		(asserts! (is-eq contract-owner tx-sender) err-not-owner)
		(asserts! (is-none (executed-at order)) err-already-executed)
		(ok (map-set money-orders order u0))
	)
)

(define-public (deposit (amount uint))
	(begin
		(asserts! (is-eq contract-owner tx-sender) err-not-owner)
		(stx-transfer? amount tx-sender (as-contract tx-sender))
	)
)

(define-public (withdraw (amount uint))
	(let ((recipient tx-sender))
		(asserts! (is-eq contract-owner tx-sender) err-not-owner)
		(as-contract (stx-transfer? amount tx-sender recipient))
	)
)
