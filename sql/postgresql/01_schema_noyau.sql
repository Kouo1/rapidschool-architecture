-- =============================================================================
-- RapidSchool Desktop - noyau du schéma relationnel (PostgreSQL, format V7)
-- -----------------------------------------------------------------------------
-- Extrait simplifié : 7 des 58 tables de la base d'une année scolaire.
-- Une base est créée par année (bd_ecolgAAAA_AAAA) : l'archivage d'une année
-- se résume à une sauvegarde pg_dump, et une année close ne peut plus être
-- modifiée par erreur depuis l'année en cours.
--
-- Choix de conception illustrés ici :
--   * clé technique (BIGSERIAL) pour l'élève et l'inscription ; le matricule
--     devient une simple information unique et modifiable (voir 02_...sql) ;
--   * eleve = identité, transition = inscription de l'élève pour l'année ;
--   * clés étrangères composées (élève + année) pour interdire une note ou une
--     absence rattachée à une inscription d'une autre année ;
--   * ON DELETE RESTRICT : on ne supprime pas un élève qui a des notes ;
--   * index sur les colonnes de jointure les plus utilisées par les bulletins.
-- Compatible PostgreSQL 9.0 à 18.
-- =============================================================================

CREATE TABLE annescolaire (
    nom_annee              varchar(64) PRIMARY KEY,          -- ex. '2025/2026'
    date_rentrer_trim2     timestamp,
    date_rentrer_trim3     timestamp
);

CREATE TABLE classe (
    code_classe            varchar(64) PRIMARY KEY,
    intitule               varchar     NOT NULL,
    section                varchar(64) NOT NULL
);

CREATE TABLE "sequence" (
    numero_sequence        varchar(64) PRIMARY KEY,           -- séquences 1 à 6
    cloturer               boolean     NOT NULL DEFAULT false  -- une séquence close n'accepte plus de notes
);

-- Identité de l'élève (stable d'une année à l'autre)
CREATE TABLE eleve (
    id                     bigserial   PRIMARY KEY,
    matricule_eleve        varchar(64) CONSTRAINT uq_matricule_eleve UNIQUE,
    nom_eleve              varchar     NOT NULL,
    prenom_eleve           varchar,
    sexe                   varchar(64) NOT NULL,
    sa_classe              varchar(64) NOT NULL REFERENCES classe (code_classe)
);

-- Inscription de l'élève pour l'année : c'est elle que référencent notes, absences, frais...
CREATE TABLE transition (
    id                     bigserial   PRIMARY KEY,
    eleve_id               bigint      NOT NULL,
    matricule_transiter    varchar(64) UNIQUE,
    sa_classe_transiter    varchar(64) NOT NULL,
    refer_annee_transiter  varchar(64) NOT NULL,
    redouble_transite      varchar(60) NOT NULL DEFAULT 'non',
    insolvable             boolean     NOT NULL DEFAULT false,

    CONSTRAINT fk_transition_eleve FOREIGN KEY (eleve_id)
        REFERENCES eleve (id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_sa_classe_transiter FOREIGN KEY (sa_classe_transiter)
        REFERENCES classe (code_classe) ON UPDATE CASCADE ON DELETE RESTRICT,
    -- cible des clés étrangères composées (inscription + année)
    CONSTRAINT uq_transition_eleve_annee UNIQUE (id, refer_annee_transiter)
);

CREATE TABLE matiere (
    code_matiere           varchar(64) NOT NULL,
    refer_classe           varchar(64) NOT NULL REFERENCES classe (code_classe),
    nom_matiere            varchar     NOT NULL,
    coefficient            numeric(4,2) NOT NULL DEFAULT 1 CHECK (coefficient > 0),
    PRIMARY KEY (code_matiere, refer_classe)
);

CREATE TABLE note (
    id_note                bigserial   PRIMARY KEY,
    refer_eleve            bigint      NOT NULL,                 -- = transition.id
    refer_matiere          varchar(64) NOT NULL,
    refer_classe           varchar(64) NOT NULL,
    refer_sequence         varchar(64) NOT NULL REFERENCES "sequence" (numero_sequence),
    refer_annee            varchar(64) NOT NULL REFERENCES annescolaire (nom_annee),
    valeur_note            numeric(4,2) CHECK (valeur_note BETWEEN 0 AND 20),

    -- une seule note par élève, matière et séquence
    CONSTRAINT uq_note UNIQUE (refer_eleve, refer_matiere, refer_sequence, refer_annee),
    CONSTRAINT fk_transition FOREIGN KEY (refer_eleve, refer_annee)
        REFERENCES transition (id, refer_annee_transiter),
    CONSTRAINT fk_note_matiere FOREIGN KEY (refer_matiere, refer_classe)
        REFERENCES matiere (code_matiere, refer_classe)
);

CREATE TABLE absence (
    refer_sequence         varchar(64) NOT NULL REFERENCES "sequence" (numero_sequence),
    refer_eleve            bigint      NOT NULL,                 -- = transition.id
    refer_anne             varchar(64) NOT NULL REFERENCES annescolaire (nom_annee),
    type_absence           varchar(64) NOT NULL,                 -- justifiée / non justifiée
    valeur_absence         integer     NOT NULL DEFAULT 0 CHECK (valeur_absence >= 0),

    PRIMARY KEY (refer_sequence, refer_eleve, type_absence),
    CONSTRAINT fk_transition FOREIGN KEY (refer_eleve, refer_anne)
        REFERENCES transition (id, refer_annee_transiter)
);

-- Index de jointure (PostgreSQL n'indexe pas automatiquement les clés étrangères)
CREATE INDEX fki_transition_eleve   ON transition (eleve_id);
CREATE INDEX fki_transition_classe  ON transition (sa_classe_transiter, refer_annee_transiter);
CREATE INDEX fki_note_matiere       ON note (refer_matiere, refer_classe);
CREATE INDEX fki_note_sequence      ON note (refer_sequence);
CREATE INDEX fki_absence_eleve      ON absence (refer_eleve);
