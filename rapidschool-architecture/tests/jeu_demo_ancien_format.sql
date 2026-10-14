-- =============================================================================
-- Jeu de données de démonstration au FORMAT V6 (ancien format)
-- L'élève y est identifié partout par son matricule (texte) : notes et absences
-- portent le matricule, qui ne peut donc jamais être corrigé.
-- Données fictives.
-- =============================================================================

CREATE TABLE annescolaire (nom_annee varchar(64) PRIMARY KEY);
CREATE TABLE classe       (code_classe varchar(64) PRIMARY KEY, intitule varchar NOT NULL, section varchar(64) NOT NULL);
CREATE TABLE "sequence"   (numero_sequence varchar(64) PRIMARY KEY, cloturer boolean NOT NULL DEFAULT false);

CREATE TABLE eleve (
    matricule_eleve varchar(64) PRIMARY KEY,
    nom_eleve varchar NOT NULL, prenom_eleve varchar, sexe varchar(64) NOT NULL,
    sa_classe varchar(64) NOT NULL REFERENCES classe (code_classe)
);
CREATE TABLE transition (
    matricule_transiter varchar(64) NOT NULL,
    sa_classe_transiter varchar(64) NOT NULL REFERENCES classe (code_classe),
    refer_annee_transiter varchar(64) NOT NULL,
    redouble_transite varchar(60) NOT NULL DEFAULT 'non',
    insolvable boolean NOT NULL DEFAULT false,
    CONSTRAINT pk_transition PRIMARY KEY (matricule_transiter, refer_annee_transiter)
);
CREATE TABLE matiere (
    code_matiere varchar(64) NOT NULL, refer_classe varchar(64) NOT NULL REFERENCES classe (code_classe),
    nom_matiere varchar NOT NULL, coefficient numeric(4,2) NOT NULL DEFAULT 1,
    PRIMARY KEY (code_matiere, refer_classe)
);
CREATE TABLE note (
    id_note serial PRIMARY KEY,
    refer_eleve varchar(64) NOT NULL,
    refer_matiere varchar(64) NOT NULL, refer_classe varchar(64) NOT NULL,
    refer_sequence varchar(64) NOT NULL REFERENCES "sequence" (numero_sequence),
    refer_annee varchar(64) NOT NULL REFERENCES annescolaire (nom_annee),
    valeur_note numeric(4,2),
    CONSTRAINT uq_note UNIQUE (refer_eleve, refer_matiere, refer_sequence, refer_annee),
    CONSTRAINT fk_transition FOREIGN KEY (refer_eleve, refer_annee)
        REFERENCES transition (matricule_transiter, refer_annee_transiter),
    CONSTRAINT fk_note_matiere FOREIGN KEY (refer_matiere, refer_classe) REFERENCES matiere (code_matiere, refer_classe)
);
-- Les anciennes versions n'avaient pas de clé étrangère sur absence : des lignes orphelines peuvent exister.
CREATE TABLE absence (
    refer_sequence varchar(64) NOT NULL REFERENCES "sequence" (numero_sequence),
    refer_eleve varchar(64) NOT NULL,
    refer_anne varchar(64) NOT NULL REFERENCES annescolaire (nom_annee),
    type_absence varchar(64) NOT NULL,
    valeur_absence integer NOT NULL DEFAULT 0,
    PRIMARY KEY (refer_sequence, refer_eleve, type_absence)
);

INSERT INTO annescolaire VALUES ('2024/2025');
INSERT INTO classe VALUES ('6E-A', 'Sixième A', 'GENERALE'), ('5E-A', 'Cinquième A', 'GENERALE');
INSERT INTO "sequence" (numero_sequence) VALUES ('1'), ('2');
INSERT INTO eleve VALUES
    ('24A001', 'ELEVE', 'Alpha',   'M', '6E-A'),
    ('24A002', 'ELEVE', 'Bravo',   'F', '6E-A'),
    ('24A003', 'ELEVE', 'Charlie', 'M', '5E-A');
INSERT INTO transition (matricule_transiter, sa_classe_transiter, refer_annee_transiter) VALUES
    ('24A001', '6E-A', '2024/2025'), ('24A002', '6E-A', '2024/2025'), ('24A003', '5E-A', '2024/2025');
INSERT INTO matiere VALUES
    ('MATH', '6E-A', 'Mathématiques', 4), ('FRAN', '6E-A', 'Français', 3), ('MATH', '5E-A', 'Mathématiques', 4);
INSERT INTO note (refer_eleve, refer_matiere, refer_classe, refer_sequence, refer_annee, valeur_note) VALUES
    ('24A001', 'MATH', '6E-A', '1', '2024/2025', 14.50), ('24A001', 'FRAN', '6E-A', '1', '2024/2025', 11.00),
    ('24A002', 'MATH', '6E-A', '1', '2024/2025', 17.25), ('24A002', 'FRAN', '6E-A', '1', '2024/2025', 15.00),
    ('24A003', 'MATH', '5E-A', '1', '2024/2025',  9.75), ('24A001', 'MATH', '6E-A', '2', '2024/2025', 12.00);
INSERT INTO absence VALUES
    ('1', '24A001', '2024/2025', 'NJ', 2), ('1', '24A003', '2024/2025', 'J', 4),
    ('1', '23Z999', '2024/2025', 'NJ', 1);   -- orpheline : élève supprimé il y a longtemps
