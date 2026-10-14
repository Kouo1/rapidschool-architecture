-- =============================================================================
-- Rôles PostgreSQL selon le principe du moindre privilège
-- -----------------------------------------------------------------------------
-- Séparation des responsabilités :
--   rs_proprietaire  : possède les objets, ne se connecte jamais (NOLOGIN) ;
--                      sert uniquement aux migrations (SET ROLE).
--   rs_application   : compte de l'application : lecture/écriture des données,
--                      aucun droit sur la structure (pas de DROP, ALTER, TRUNCATE).
--   rs_lecture       : rapports et statistiques : lecture seule.
--   rs_sauvegarde    : pg_dump planifié : lecture seule, aucune écriture.
-- Les comptes de connexion héritent d'un rôle de groupe ; on retire un accès
-- en révoquant l'appartenance, sans toucher aux droits des tables.
--
-- Exécution (superutilisateur), une fois par base d'année :
--   psql -v ON_ERROR_STOP=1 -d bd_ecolg2025_2026 -v base=bd_ecolg2025_2026 -f 04_roles_moindre_privilege.sql
-- Les mots de passe sont définis ensuite avec \password, jamais dans un script versionné.
-- =============================================================================

-- Rôles de groupe (créés une seule fois pour le serveur)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rs_proprietaire') THEN CREATE ROLE rs_proprietaire NOLOGIN; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rs_application')  THEN CREATE ROLE rs_application  NOLOGIN; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rs_lecture')      THEN CREATE ROLE rs_lecture      NOLOGIN; END IF;
    -- comptes de connexion (mot de passe à définir avec \password)
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rs_app')        THEN CREATE ROLE rs_app        LOGIN IN ROLE rs_application; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rs_rapport')    THEN CREATE ROLE rs_rapport    LOGIN IN ROLE rs_lecture; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rs_sauvegarde') THEN CREATE ROLE rs_sauvegarde LOGIN IN ROLE rs_lecture; END IF;
END $$;

-- Personne ne se connecte « par défaut » : la connexion est accordée explicitement
REVOKE ALL     ON DATABASE :"base" FROM PUBLIC;
GRANT  CONNECT ON DATABASE :"base" TO rs_application, rs_lecture;

-- Le schéma public n'est plus modifiable par tout le monde (comportement par défaut avant PG 15)
REVOKE ALL    ON SCHEMA public FROM PUBLIC;
GRANT  USAGE  ON SCHEMA public TO rs_application, rs_lecture;
GRANT  ALL    ON SCHEMA public TO rs_proprietaire;

-- Les objets appartiennent au rôle propriétaire, pas au compte de l'application
DO $$
DECLARE o record;
BEGIN
    FOR o IN SELECT format('ALTER TABLE %I.%I OWNER TO rs_proprietaire', schemaname, tablename) AS cmd
               FROM pg_tables WHERE schemaname = 'public'
    LOOP
        EXECUTE o.cmd;   -- les séquences liées (bigserial) suivent leur table
    END LOOP;
END $$;

-- Application : données uniquement
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA public TO rs_application;
GRANT USAGE, SELECT                  ON ALL SEQUENCES IN SCHEMA public TO rs_application;

-- Lecture seule : rapports et sauvegardes
GRANT SELECT ON ALL TABLES    IN SCHEMA public TO rs_lecture;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO rs_lecture;   -- pg_dump lit la valeur des séquences

-- Les tables créées plus tard par une migration reçoivent les mêmes droits
ALTER DEFAULT PRIVILEGES FOR ROLE rs_proprietaire IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO rs_application;
ALTER DEFAULT PRIVILEGES FOR ROLE rs_proprietaire IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO rs_application;
ALTER DEFAULT PRIVILEGES FOR ROLE rs_proprietaire IN SCHEMA public
    GRANT SELECT ON TABLES TO rs_lecture;
ALTER DEFAULT PRIVILEGES FOR ROLE rs_proprietaire IN SCHEMA public
    GRANT SELECT ON SEQUENCES TO rs_lecture;

-- Contrôle : droits effectifs par rôle
SELECT r.rolname,
       has_table_privilege(r.rolname, 'note', 'SELECT') AS lire,
       has_table_privilege(r.rolname, 'note', 'INSERT') AS ecrire,
       has_table_privilege(r.rolname, 'note', 'TRUNCATE') AS vider
  FROM pg_roles r
 WHERE r.rolname IN ('rs_app', 'rs_rapport', 'rs_sauvegarde')
 ORDER BY r.rolname;
