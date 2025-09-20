;; GameVault - Decentralized Gaming Achievement Platform
;; A blockchain-based platform for gaming achievements, leaderboards,
;; and cross-game rewards

;; Contract constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-unauthorized (err u103))
(define-constant err-invalid-input (err u104))
(define-constant err-insufficient-tokens (err u105))

;; Token constants
(define-constant token-name "GameVault Achievement Token")
(define-constant token-symbol "GAT")
(define-constant token-decimals u6)
(define-constant token-max-supply u150000000000) ;; 150k tokens with 6 decimals

;; Reward amounts (in micro-tokens)
(define-constant reward-achievement u5000000) ;; 5 GAT
(define-constant reward-leaderboard u8000000) ;; 8 GAT
(define-constant reward-tournament u15000000) ;; 15 GAT
(define-constant reward-milestone u20000000) ;; 20 GAT

;; Data variables
(define-data-var total-supply uint u0)
(define-data-var next-game-id uint u1)
(define-data-var next-tournament-id uint u1)

;; Token balances
(define-map token-balances principal uint)

;; Gamer profiles
(define-map gamer-profiles
  principal
  {
    username: (string-ascii 32),
    gamer-level: uint, ;; 1-10
    total-achievements: uint,
    games-played: uint,
    tournaments-won: uint,
    total-score: uint,
    reputation: uint,
    join-date: uint,
    last-activity: uint
  }
)

;; Game registry
(define-map game-registry
  uint
  {
    game-title: (string-ascii 64),
    game-genre: (string-ascii 24), ;; "action", "puzzle", "strategy", "rpg", "sports"
    developer: principal,
    max-score: uint,
    difficulty: uint, ;; 1-5
    active: bool
  }
)

;; Player achievements
(define-map player-achievements
  { game-id: uint, player: principal }
  {
    high-score: uint,
    achievements-unlocked: uint,
    completion-percentage: uint,
    play-time-hours: uint,
    last-played: uint,
    verified: bool
  }
)

;; Game tournaments
(define-map game-tournaments
  uint
  {
    organizer: principal,
    game-id: uint,
    tournament-name: (string-ascii 64),
    entry-fee: uint,
    max-participants: uint,
    current-participants: uint,
    prize-pool: uint,
    start-date: uint,
    end-date: uint,
    active: bool
  }
)

;; Tournament participation
(define-map tournament-participation
  { tournament-id: uint, participant: principal }
  {
    entry-date: uint,
    final-score: uint,
    rank: uint,
    prize-won: uint
  }
)

;; Leaderboards
(define-map game-leaderboards
  { game-id: uint, rank: uint }
  {
    player: principal,
    score: uint,
    achievement-date: uint
  }
)

;; Gaming milestones
(define-map gaming-milestones
  { gamer: principal, milestone: (string-ascii 32) }
  {
    achievement-date: uint,
    milestone-value: uint,
    reward-earned: uint
  }
)

;; Helper function to get or create profile
(define-private (get-or-create-profile (gamer principal))
  (match (map-get? gamer-profiles gamer)
    profile profile
    {
      username: "",
      gamer-level: u1,
      total-achievements: u0,
      games-played: u0,
      tournaments-won: u0,
      total-score: u0,
      reputation: u100,
      join-date: stacks-block-height,
      last-activity: stacks-block-height
    }
  )
)

;; Token functions
(define-read-only (get-name)
  (ok token-name)
)

(define-read-only (get-symbol)
  (ok token-symbol)
)

(define-read-only (get-decimals)
  (ok token-decimals)
)

(define-read-only (get-balance (user principal))
  (ok (default-to u0 (map-get? token-balances user)))
)

(define-read-only (get-total-supply)
  (ok (var-get total-supply))
)

(define-private (mint-tokens (recipient principal) (amount uint))
  (let (
    (current-balance (default-to u0 (map-get? token-balances recipient)))
    (new-balance (+ current-balance amount))
    (new-total-supply (+ (var-get total-supply) amount))
  )
    (asserts! (<= new-total-supply token-max-supply) err-invalid-input)
    (map-set token-balances recipient new-balance)
    (var-set total-supply new-total-supply)
    (ok amount)
  )
)

;; Register new game
(define-public (register-game (game-title (string-ascii 64)) (game-genre (string-ascii 24)) (max-score uint) (difficulty uint))
  (let (
    (game-id (var-get next-game-id))
  )
    (asserts! (> (len game-title) u0) err-invalid-input)
    (asserts! (> max-score u0) err-invalid-input)
    (asserts! (and (>= difficulty u1) (<= difficulty u5)) err-invalid-input)
    
    (map-set game-registry game-id {
      game-title: game-title,
      game-genre: game-genre,
      developer: tx-sender,
      max-score: max-score,
      difficulty: difficulty,
      active: true
    })
    
    (var-set next-game-id (+ game-id u1))
    (print {action: "game-registered", game-id: game-id, developer: tx-sender})
    (ok game-id)
  )
)

;; Submit game achievement
(define-public (submit-achievement (game-id uint) (score uint) (achievements-unlocked uint) 
                                  (completion-percentage uint) (play-time-hours uint))
  (let (
    (game (unwrap! (map-get? game-registry game-id) err-not-found))
    (profile (get-or-create-profile tx-sender))
    (existing-achievement (map-get? player-achievements {game-id: game-id, player: tx-sender}))
  )
    (asserts! (get active game) err-invalid-input)
    (asserts! (<= score (get max-score game)) err-invalid-input)
    (asserts! (<= completion-percentage u100) err-invalid-input)
    
    ;; Check if new high score
    (let (
      (is-new-high-score
        (match existing-achievement
          existing (> score (get high-score existing))
          true
        ))
    )
      ;; Update or create achievement
      (map-set player-achievements {game-id: game-id, player: tx-sender} {
        high-score: (match existing-achievement
          existing (if (> score (get high-score existing)) score (get high-score existing))
          score
        ),
        achievements-unlocked: achievements-unlocked,
        completion-percentage: completion-percentage,
        play-time-hours: play-time-hours,
        last-played: stacks-block-height,
        verified: false
      })
      
      ;; Update profile if new game
      (if (is-none existing-achievement)
        (map-set gamer-profiles tx-sender
          (merge profile {
            games-played: (+ (get games-played profile) u1),
            total-achievements: (+ (get total-achievements profile) achievements-unlocked),
            total-score: (+ (get total-score profile) score),
            gamer-level: (+ (get gamer-level profile) (get difficulty game)),
            last-activity: stacks-block-height
          })
        )
        (map-set gamer-profiles tx-sender
          (merge profile {
            total-score: (+ (- (get total-score profile) 
                            (get high-score (unwrap-panic existing-achievement))) score),
            last-activity: stacks-block-height
          })
        )
      )
      
      ;; Award achievement tokens
      (try! (mint-tokens tx-sender reward-achievement))
      
      ;; Bonus for high completion
      (if (>= completion-percentage u90)
        (begin
          (try! (mint-tokens tx-sender u3000000)) ;; 3 GAT bonus
          true
        )
        true
      )
      
      (print {action: "achievement-submitted", game-id: game-id, player: tx-sender, score: score})
      (ok true)
    )
  )
)

;; Create tournament
(define-public (create-tournament (game-id uint) (tournament-name (string-ascii 64)) (entry-fee uint) 
                                 (max-participants uint) (duration-days uint))
  (let (
    (tournament-id (var-get next-tournament-id))
    (game (unwrap! (map-get? game-registry game-id) err-not-found))
    (profile (get-or-create-profile tx-sender))
  )
    (asserts! (> (len tournament-name) u0) err-invalid-input)
    (asserts! (> max-participants u1) err-invalid-input)
    (asserts! (and (>= duration-days u1) (<= duration-days u30)) err-invalid-input)
    (asserts! (get active game) err-invalid-input)
    (asserts! (>= (get reputation profile) u150) err-unauthorized)
    
    (map-set game-tournaments tournament-id {
      organizer: tx-sender,
      game-id: game-id,
      tournament-name: tournament-name,
      entry-fee: entry-fee,
      max-participants: max-participants,
      current-participants: u0,
      prize-pool: u0,
      start-date: stacks-block-height,
      end-date: (+ stacks-block-height duration-days),
      active: true
    })
    
    (var-set next-tournament-id (+ tournament-id u1))
    (print {action: "tournament-created", tournament-id: tournament-id, organizer: tx-sender})
    (ok tournament-id)
  )
)

;; Join tournament
(define-public (join-tournament (tournament-id uint))
  (let (
    (tournament (unwrap! (map-get? game-tournaments tournament-id) err-not-found))
  )
    (asserts! (get active tournament) err-invalid-input)
    (asserts! (< stacks-block-height (get end-date tournament)) err-invalid-input)
    (asserts! (< (get current-participants tournament) (get max-participants tournament)) err-invalid-input)
    (asserts! (not (is-eq tx-sender (get organizer tournament))) err-unauthorized)
    (asserts! (is-none (map-get? tournament-participation {tournament-id: tournament-id, participant: tx-sender})) err-already-exists)
    
    ;; Add participant
    (map-set tournament-participation {tournament-id: tournament-id, participant: tx-sender} {
      entry-date: stacks-block-height,
      final-score: u0,
      rank: u0,
      prize-won: u0
    })
    
    ;; Update tournament
    (map-set game-tournaments tournament-id
      (merge tournament {
        current-participants: (+ (get current-participants tournament) u1),
        prize-pool: (+ (get prize-pool tournament) (get entry-fee tournament))
      })
    )
    
    (print {action: "tournament-joined", tournament-id: tournament-id, participant: tx-sender})
    (ok true)
  )
)

;; Submit tournament score
(define-public (submit-tournament-score (tournament-id uint) (final-score uint))
  (let (
    (tournament (unwrap! (map-get? game-tournaments tournament-id) err-not-found))
    (participation (unwrap! (map-get? tournament-participation {tournament-id: tournament-id, participant: tx-sender}) err-not-found))
    (game (unwrap! (map-get? game-registry (get game-id tournament)) err-not-found))
  )
    (asserts! (get active tournament) err-invalid-input)
    (asserts! (<= final-score (get max-score game)) err-invalid-input)
    (asserts! (is-eq (get final-score participation) u0) err-already-exists)
    
    ;; Update participation with score
    (map-set tournament-participation {tournament-id: tournament-id, participant: tx-sender}
      (merge participation {final-score: final-score})
    )
    
    ;; Award tournament participation tokens
    (try! (mint-tokens tx-sender reward-tournament))
    
    (print {action: "tournament-score-submitted", tournament-id: tournament-id, participant: tx-sender, score: final-score})
    (ok true)
  )
)

;; Update leaderboard
(define-public (update-leaderboard (game-id uint) (player principal) (score uint) (rank uint))
  (let (
    (game (unwrap! (map-get? game-registry game-id) err-not-found))
  )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (get active game) err-invalid-input)
    (asserts! (> rank u0) err-invalid-input)
    (asserts! (<= score (get max-score game)) err-invalid-input)
    
    (map-set game-leaderboards {game-id: game-id, rank: rank} {
      player: player,
      score: score,
      achievement-date: stacks-block-height
    })
    
    ;; Award leaderboard tokens to player
    (try! (mint-tokens player reward-leaderboard))
    
    (print {action: "leaderboard-updated", game-id: game-id, player: player, rank: rank})
    (ok true)
  )
)

;; Claim gaming milestone
(define-public (claim-gaming-milestone (milestone (string-ascii 32)))
  (let (
    (profile (get-or-create-profile tx-sender))
  )
    (asserts! (is-none (map-get? gaming-milestones {gamer: tx-sender, milestone: milestone})) err-already-exists)
    
    ;; Check milestone requirements
    (let (
      (milestone-met
        (if (is-eq milestone "gamer-rookie-10") (>= (get games-played profile) u10)
        (if (is-eq milestone "achievement-hunter-50") (>= (get total-achievements profile) u50)
        (if (is-eq milestone "score-master-10000") (>= (get total-score profile) u10000)
        (if (is-eq milestone "tournament-champion-5") (>= (get tournaments-won profile) u5)
        false)))))
    )
      (asserts! milestone-met err-unauthorized)
      
      ;; Record milestone
      (map-set gaming-milestones {gamer: tx-sender, milestone: milestone} {
        achievement-date: stacks-block-height,
        milestone-value: (get total-score profile),
        reward-earned: reward-milestone
      })
      
      ;; Award milestone tokens
      (try! (mint-tokens tx-sender reward-milestone))
      
      (print {action: "gaming-milestone-claimed", gamer: tx-sender, milestone: milestone})
      (ok true)
    )
  )
)

;; Update username
(define-public (update-username (new-username (string-ascii 32)))
  (let (
    (profile (get-or-create-profile tx-sender))
  )
    (asserts! (> (len new-username) u0) err-invalid-input)
    (map-set gamer-profiles tx-sender (merge profile {username: new-username}))
    (print {action: "username-updated", gamer: tx-sender, username: new-username})
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-gamer-profile (gamer principal))
  (map-get? gamer-profiles gamer)
)

(define-read-only (get-game-info (game-id uint))
  (map-get? game-registry game-id)
)

(define-read-only (get-player-achievement (game-id uint) (player principal))
  (map-get? player-achievements {game-id: game-id, player: player})
)

(define-read-only (get-tournament-info (tournament-id uint))
  (map-get? game-tournaments tournament-id)
)

(define-read-only (get-tournament-participation (tournament-id uint) (participant principal))
  (map-get? tournament-participation {tournament-id: tournament-id, participant: participant})
)

(define-read-only (get-leaderboard-entry (game-id uint) (rank uint))
  (map-get? game-leaderboards {game-id: game-id, rank: rank})
)

(define-read-only (get-gaming-milestone (gamer principal) (milestone (string-ascii 32)))
  (map-get? gaming-milestones {gamer: gamer, milestone: milestone})
)

;; Admin functions
(define-public (verify-achievement (game-id uint) (player principal))
  (let (
    (achievement (unwrap! (map-get? player-achievements {game-id: game-id, player: player}) err-not-found))
  )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set player-achievements {game-id: game-id, player: player} (merge achievement {verified: true}))
    (print {action: "achievement-verified", game-id: game-id, player: player})
    (ok true)
  )
)

(define-public (deactivate-game (game-id uint))
  (let (
    (game (unwrap! (map-get? game-registry game-id) err-not-found))
  )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set game-registry game-id (merge game {active: false}))
    (print {action: "game-deactivated", game-id: game-id})
    (ok true)
  )
)