# RapidSchool web : plateforme SaaS multi-établissement

En ligne : <https://www.rapidschool.cm>

## Architecture

```mermaid
flowchart LR
    U[Navigateur<br/>React + Vite] -->|HTTPS, jeton Sanctum| A[API REST Laravel<br/>VPS Linux]
    A --> DB[(MySQL 8<br/>base partagée)]
    A -->|file d'attente| Q[Jobs Laravel]
    A -->|HTTP| P[Service PDF<br/>Node.js + Puppeteer<br/>AWS EC2]
    P -->|bulletins, cartes,<br/>listes en PDF| A
```

- **Front** : React/Vite, construit et servi en fichiers statiques.
- **API** : Laravel, environ 280 routes, authentification par jeton (Sanctum), double authentification optionnelle.
- **PDF** : rendu HTML → PDF délégué à un service Node.js/Puppeteer sur EC2, pour ne pas
  charger le serveur applicatif lors de l'impression des bulletins de toute une classe.

## Multi-tenant : base partagée, isolation par établissement

Tous les établissements partagent la même base ; chaque donnée métier porte
`etablissement_id` et `annee_scolaire_id`.

```mermaid
erDiagram
    ETABLISSEMENTS ||--o{ AFFECTATIONS_PERSONNEL : emploie
    PERSONNEL ||--o{ AFFECTATIONS_PERSONNEL : "est affecté"
    ANNEE_SCOLAIRES ||--o{ AFFECTATIONS_PERSONNEL : pour
    ETABLISSEMENTS ||--o{ CLASSES : ouvre
    CLASSES ||--o{ INSCRIPTIONS_ELEVES : regroupe
    ELEVES ||--o{ INSCRIPTIONS_ELEVES : "s'inscrit"
    AFFECTATIONS_PERSONNEL ||--o{ ENSEIGNANT_MATIERE_CLASSE : enseigne
    CLASSES ||--o{ ENSEIGNANT_MATIERE_CLASSE : "reçoit"
    INSCRIPTIONS_ELEVES ||--o{ NOTES : obtient
    ENSEIGNANT_MATIERE_CLASSE ||--o{ NOTES : "saisies dans"
    NOTES ||--o{ NOTES_HISTORIQUE : "tracée par"

    AFFECTATIONS_PERSONNEL {
        bigint id PK
        bigint personnel_id FK
        bigint etablissement_id FK
        bigint annee_scolaire_id FK
        varchar role_systeme "droits dans CET établissement"
    }
    INSCRIPTIONS_ELEVES {
        bigint id PK
        bigint eleve_id FK
        bigint classe_id FK
        bigint etablissement_id FK
        bigint annee_scolaire_id FK
        enum statut
    }
    NOTES {
        bigint id PK
        bigint inscription_eleve_id FK
        bigint enseignant_matiere_classe_id FK
        bigint sequence_id FK
        decimal note
    }
    NOTES_HISTORIQUE {
        bigint id PK
        bigint note_id FK
        decimal ancienne_valeur
        decimal nouvelle_valeur
        bigint modifie_par_affectation_id FK
        timestamp modifie_le
    }
```

**Points de conception**
- **Les droits passent par l'affectation, pas par la personne.** Un enseignant peut travailler dans
  deux établissements avec des rôles différents ; son rôle est porté par `affectations_personnel`
  (personne × établissement × année).
- **Contrôle d'accès à chaque requête** : un middleware vérifie que l'utilisateur a une affectation
  active dans l'établissement demandé dans l'URL ; sinon `403`. Seul le rôle super-administrateur y échappe.
- **Unicité dans le bon périmètre** : `UNIQUE (code, etablissement_id, annee_scolaire_id)` sur les classes,
  deux écoles peuvent avoir chacune leur « 6e A ».
- **Traçabilité des notes** : toute modification de valeur, y compris par un administrateur, est
  enregistrée avec l'ancienne valeur, la nouvelle, l'auteur et l'heure.
- **Intégrité** : clés étrangères `ON DELETE RESTRICT` sur toute la chaîne élève → inscription → note.
- **Migrations versionnées** (Laravel), y compris le DDL SQL d'origine reproduit à l'identique
  pour les tables reprises d'une base existante.
