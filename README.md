# Roma Aeterna

**MMORPG sincrono in terza persona ambientato nell'Antica Roma**
Stile Dark Age of Camelot — combattimento action, tre fazioni in guerra, RvR epico.

---

## Concept

Roma Aeterna è un MMORPG server-autoritativo dove tre grandi fazioni si scontrano per il controllo delle terre di frontiera:

| Fazione | Colore | Stile |
|---------|--------|-------|
| **Romani** | Rosso Imperiale | Disciplina, formazioni, magia divina |
| **Galli** | Verde Celtico | Natura, druidismo, guerriglia |
| **Germani** | Blu Nordico | Furia, berserker, sciamanesimo |

---

## Classi

### Romani
- **Legionario** — Tank/Melee. Scudo, gladio, formazione Testudo.
- **Sagittario** — Ranged DPS. Arco, frecce speciali, trappole.
- **Medicus** — Healer. Guarigione, resurrezione, benedizioni divine.
- **Gladiatore** — Melee DPS. Stili misti (reziario, secutore, mirmillone).

### Galli
- **Guerriero Celtico** — Melee DPS. Spade a due mani, velocità.
- **Druido** — Hybrid Healer/Caster. Natura, trasformazioni, HoT.
- **Cacciatore** — Ranged DPS. Arco, trappole, animale compagno.

### Germani
- **Berserker** — Melee DPS. Meccanica RAGE, più danni a bassa vita.
- **Sciamano** — Caster/Support. Maledizioni, totem, visioni.
- **Guardia** — Tank. Grande scudo, controllo della folla.

---

## Sistemi Core

### Combattimento Action
- Targeting semi-automatico (Tab target + mirino libero)
- Dodge con costo Endurance
- Auto-attack + 10 slot abilità hotbar
- Casting con barra dedicata, interrompibile
- Colpi critici, parata, blocco, schivata
- Coda abilità (DAoC-style)

### RvR — Realm vs Realm
- Zona frontiera livello 30+ (Frontiera del Reno)
- **Forti** (Keep) da assaltare/difendere
- **Torri** come punti intermedi
- **Reliquie** — oggetti catturabili che danno buff fazione-wide
- Sistema punteggio per campagna (vittoria a 5000 punti)
- Ricompense: punti regno, armature RvR, titoli

### Progressione
- Livello massimo 50
- XP da mostri, quest, e kill RvR
- Sistema di abilità a sblocco per livello
- Equipaggiamento: Common → Uncommon → Rare → Epic → Legendary
- Reputazione fazione per tier di equipaggiamento RvR

### Mondo
| Zona | Livelli | Tipo |
|------|---------|------|
| Foro Romano | 1-10 | Sicura (Romani) |
| Via Appia | 5-15 | PvE |
| Foreste Galliche | 1-10 | Sicura (Galli) |
| Selva Nera | 5-15 | PvE |
| Frontiera del Reno | 30-50 | **RvR** |
| Dungeons | vari | Istanziati |

---

## Architettura Tecnica

```
Client (Godot 4)
    ↕ ENet UDP
Server Dedicato (Godot Headless)
    ↕
Database (SQLite / PostgreSQL)
```

### Server-Autoritativo
- Il server gestisce tutta la logica di gioco
- I client inviano solo input (direzione, azioni)
- Il server trasmette lo stato del mondo a 20 Hz
- Client-side prediction per movimento fluido

### Network Manager
- ENet per bassa latenza
- RPC affidabili per abilità/chat
- RPC inaffidabili per posizioni

---

## Setup Sviluppo

### Requisiti
- Godot 4.2+
- (opzionale) SQLite plugin per Godot

### Avvio Server Locale
```bash
godot --headless --dedicated-server
```

### Avvio Client
```bash
godot
# Poi: "Ospita Partita Locale" per gioco singolo/test
```

### Variabili Ambiente Server
```
SERVER_PORT=7777
MAX_PLAYERS=500
```

---

## Struttura Progetto

```
/
├── project.godot
├── scripts/
│   ├── autoloads/       # GameManager, NetworkManager, DataManager, EventBus
│   ├── character/       # Character, PlayerCharacter, NPCCharacter, CharacterStats
│   │   └── classes/     # Meccaniche specifiche per classe
│   ├── combat/          # Ability, AbilityManager, CombatSystem
│   ├── faction/         # RvRManager
│   ├── items/           # Item, Inventory
│   ├── quests/          # Quest, QuestManager
│   ├── world/           # WorldZone, SpawnManager
│   ├── ui/              # HUD, MainMenu
│   └── server/          # DedicatedServer
├── scenes/
│   ├── game/            # World.tscn, PlayerCharacter.tscn
│   └── menus/           # MainMenu.tscn
└── data/
    ├── classes/         # JSON classi
    ├── abilities/       # JSON abilità
    ├── items/           # JSON oggetti
    ├── quests/          # JSON missioni
    └── zones/           # JSON zone
```

---

## Roadmap

- [ ] **Fase 1** — Core gameplay (movimento, combattimento, abilità) ✅ foundation
- [ ] **Fase 2** — Contenuto PvE (dungeon, boss, quest chain)
- [ ] **Fase 3** — RvR completo (forti assediabili, reliquie)
- [ ] **Fase 4** — Sistema gilde / Legioni
- [ ] **Fase 5** — Economy (commercio, artigianato)
- [ ] **Fase 6** — Polish & bilanciamento
