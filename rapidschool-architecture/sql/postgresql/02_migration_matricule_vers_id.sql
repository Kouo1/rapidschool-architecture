-- =============================================================================
-- Migration V6 -> V7 : remplacer la clé naturelle (matricule) par une clé technique
-- -----------------------------------------------------------------------------
-- PROBLÈME
--   En V6, l'élève est identifié partout par son matricule (texte). Notes et
--   absences portent ce matricule : une faute de frappe à l'inscription ne peut
--   plus être corrigée sans casser les liens, et les jointures se font sur du texte.
--
-- SOLUTION
--   eleve.id et transition.id (bigint) deviennent les clés primaires ; les tables
--   rattachées reçoivent transition.id à la place du matricule, qui devient une
--   simple colonne UNIQUE modifiable.
--
-- GARANTIES
--   * une seule transaction : en cas d'erreur, PostgreSQL annule tout ;
--   * verrou exclusif : aucun autre poste ne lit ni n'écrit pendant la migration ;
--   * lignes orphelines (sans élève) mises de côté dans une table dédiée, pas perdues ;
--   * contrôle final : nombre de lignes ET empreinte MD5 du contenu identiques
--     avant / après, sinon la transaction est annulée.
--
-- Version simplifiée (2 tables rattachées) de la conversion livrée dans
-- RapidSchool V7, qui traite 8 tables et s'exécute depuis l'application après
-- une sauvegarde pg_dump automatique.
--
-- Exécution :  psql -v ON_ERROR_STOP=1 -d base_annee -f 02_migration_matricule_vers_id.sql
-- Compatible PostgreSQL 9.0 à 18.
-- =============================================================================

BEGIN;

SET LOCAL statement_timeout = '30s';      -- ne pas attendre indéfiniment un poste qui garde la base
LOCK TABLE eleve, transition, note, absence IN ACCESS EXCLUSIVE MODE;
SET LOCAL statement_timeout = 0;

-- ---------------------------------------------------------------------------
-- 1. Contrôles préalables : une anomalie arrête tout avant la moindre modification
-- ---------------------------------------------------------------------------
DO $$
DECLARE n bigint;
BEGIN
    SELECT count(*) INTO n FROM transition t
     WHERE NOT EXISTS (SELECT 1 FROM eleve e WHERE e.matricule_eleve = t.matricule_transiter);
    IF n > 0 THEN
        RAISE EXCEPTION '% inscription(s) sans élève correspondant : migration annulée', n;
    END IF;

    SELECT count(*) INTO n FROM (SELECT matricule_transiter FROM transition
                                 GROUP BY matricule_transiter HAVING count(*) > 1) d;
    IF n > 0 THEN
        RAISE EXCEPTION '% matricule(s) inscrit(s) deux fois dans l''année : migration annulée', n;
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 2. Orphelins : lignes d'absence sans inscription (anciennes versions sans clé étrangère)
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS rs_conv_orphelins_absence;
CREATE TABLE rs_conv_orphelins_absence AS
    SELECT a.* FROM absence a
     WHERE NOT EXISTS (SELECT 1 FROM transition t
                        WHERE t.matricule_transiter = a.refer_eleve
                          AND t.refer_annee_transiter = a.refer_anne);
DELETE FROM absence a
 WHERE NOT EXISTS (SELECT 1 FROM transition t
                    WHERE t.matricule_transiter = a.refer_eleve
                      AND t.refer_annee_transiter = a.refer_anne);

-- ---------------------------------------------------------------------------
-- 3. Empreinte du contenu AVANT (par matricule, pour comparer après conversion)
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE empreinte_avant ON COMMIT DROP AS
SELECT 'note'::text AS table_nom, count(*) AS lignes,
       md5(coalesce(string_agg(refer_eleve || '|' || refer_matiere || '|' || refer_sequence || '|'
                               || coalesce(valeur_note::text, ''), ','
                               ORDER BY refer_eleve, refer_matiere, refer_sequence), '')) AS empreinte
  FROM note
UNION ALL
SELECT 'absence', count(*),
       md5(coalesce(string_agg(refer_eleve || '|' || refer_sequence || '|' || type_absence || '|'
                               || valeur_absence, ','
                               ORDER BY refer_eleve, refer_sequence, type_absence), ''))
  FROM absence;

-- ---------------------------------------------------------------------------
-- 4. Élèves : clé technique, le matricule devient une information unique
-- ---------------------------------------------------------------------------
ALTER TABLE note DROP CONSTRAINT fk_transition;

ALTER TABLE eleve ADD COLUMN id bigserial;
ALTER TABLE eleve DROP CONSTRAINT eleve_pkey;
ALTER TABLE eleve ADD CONSTRAINT eleve_pkey PRIMARY KEY (id);
ALTER TABLE eleve ALTER COLUMN matricule_eleve DROP NOT NULL;
ALTER TABLE eleve ADD CONSTRAINT uq_matricule_eleve UNIQUE (matricule_eleve);

-- ---------------------------------------------------------------------------
-- 5. Inscriptions : même numéro que l'élève, séquence propre pour les suivantes
-- ---------------------------------------------------------------------------
ALTER TABLE transition ADD COLUMN id bigint;
ALTER TABLE transition ADD COLUMN eleve_id bigint;
UPDATE transition SET id = e.id, eleve_id = e.id
  FROM eleve e WHERE e.matricule_eleve = transition.matricule_transiter;

CREATE SEQUENCE transition_id_seq OWNED BY transition.id;
DO $$ BEGIN
    PERFORM setval('transition_id_seq', (SELECT coalesce(max(id), 0) + 1 FROM transition), false);
END $$;
ALTER TABLE transition ALTER COLUMN id SET DEFAULT nextval('transition_id_seq');
ALTER TABLE transition ALTER COLUMN id SET NOT NULL;
ALTER TABLE transition ALTER COLUMN eleve_id SET NOT NULL;

ALTER TABLE transition DROP CONSTRAINT pk_transition;
ALTER TABLE transition ADD CONSTRAINT transition_pkey PRIMARY KEY (id);
ALTER TABLE transition ALTER COLUMN matricule_transiter DROP NOT NULL;
ALTER TABLE transition ADD CONSTRAINT transition_matricule_transiter_key UNIQUE (matricule_transiter);
ALTER TABLE transition ADD CONSTRAINT uq_transition_eleve_annee UNIQUE (id, refer_annee_transiter);
ALTER TABLE transition ADD CONSTRAINT fk_transition_eleve FOREIGN KEY (eleve_id)
    REFERENCES eleve (id) ON UPDATE CASCADE ON DELETE RESTRICT;

-- ---------------------------------------------------------------------------
-- 6. Tables rattachées : matricule -> transition.id, puis changement de type
-- ---------------------------------------------------------------------------
UPDATE note SET refer_eleve = t.id::text
  FROM transition t WHERE t.matricule_transiter = note.refer_eleve;
ALTER TABLE note ALTER COLUMN refer_eleve TYPE bigint USING refer_eleve::bigint;
ALTER TABLE note ALTER COLUMN id_note TYPE bigint;

UPDATE absence SET refer_eleve = t.id::text
  FROM transition t WHERE t.matricule_transiter = absence.refer_eleve;
ALTER TABLE absence ALTER COLUMN refer_eleve TYPE bigint USING refer_eleve::bigint;

-- ---------------------------------------------------------------------------
-- 7. Contraintes et index dans leur forme V7 (absence gagne une clé étrangère)
-- ---------------------------------------------------------------------------
ALTER TABLE note ADD CONSTRAINT fk_transition FOREIGN KEY (refer_eleve, refer_annee)
    REFERENCES transition (id, refer_annee_transiter);
ALTER TABLE absence ADD CONSTRAINT fk_transition FOREIGN KEY (refer_eleve, refer_anne)
    REFERENCES transition (id, refer_annee_transiter);

CREATE INDEX fki_transition_eleve ON transition (eleve_id);
CREATE INDEX fki_absence_eleve    ON absence (refer_eleve);

-- ---------------------------------------------------------------------------
-- 8. Contrôle final : mêmes lignes, mêmes valeurs, rattachées aux mêmes élèves
-- ---------------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
    FOR r IN
        WITH apres AS (
            SELECT 'note'::text AS table_nom, count(*) AS lignes,
                   md5(coalesce(string_agg(t.matricule_transiter || '|' || n.refer_matiere || '|' || n.refer_sequence || '|'
                                           || coalesce(n.valeur_note::text, ''), ','
                                           ORDER BY t.matricule_transiter, n.refer_matiere, n.refer_sequence), '')) AS empreinte
              FROM note n JOIN transition t ON t.id = n.refer_eleve
            UNION ALL
            SELECT 'absence', count(*),
                   md5(coalesce(string_agg(t.matricule_transiter || '|' || a.refer_sequence || '|' || a.type_absence || '|'
                                           || a.valeur_absence, ','
                                           ORDER BY t.matricule_transiter, a.refer_sequence, a.type_absence), ''))
              FROM absence a JOIN transition t ON t.id = a.refer_eleve
        )
        SELECT av.table_nom, av.lignes AS l_avant, ap.lignes AS l_apres,
               av.empreinte = ap.empreinte AS identique
          FROM empreinte_avant av JOIN apres ap USING (table_nom)
    LOOP
        IF r.l_avant <> r.l_apres OR NOT r.identique THEN
            RAISE EXCEPTION 'Contrôle échoué sur % (% lignes avant, % après) : migration annulée',
                            r.table_nom, r.l_avant, r.l_apres;
        END IF;
        RAISE NOTICE 'Contrôle OK : % (% lignes, contenu identique)', r.table_nom, r.l_apres;
    END LOOP;
END $$;

COMMIT;
