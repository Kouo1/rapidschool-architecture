-- =============================================================================
-- Requêtes de bulletin : moyenne pondérée et rang en UNE requête
-- -----------------------------------------------------------------------------
-- Plutôt que d'interroger la base élève par élève et matière par matière
-- (des milliers d'allers-retours pour une classe), le calcul est confié à
-- PostgreSQL : agrégation + fonction de fenêtre RANK(), une requête par classe.
-- Schéma : 01_schema_noyau.sql
-- =============================================================================

-- Moyenne pondérée par les coefficients, rang dans la classe, pour une séquence
-- Paramètres (psql) : -v classe="'6E-A'" -v sequence="'1'" -v annee="'2024/2025'"
WITH moyennes AS (
    SELECT t.id                                         AS inscription,
           e.nom_eleve || ' ' || coalesce(e.prenom_eleve, '') AS eleve,
           sum(n.valeur_note * m.coefficient)            AS points,
           sum(m.coefficient)                            AS coefficients,
           count(n.valeur_note)                          AS matieres_notees
      FROM transition t
      JOIN eleve   e ON e.id = t.eleve_id
      JOIN note    n ON n.refer_eleve = t.id AND n.refer_annee = t.refer_annee_transiter
      JOIN matiere m ON m.code_matiere = n.refer_matiere AND m.refer_classe = n.refer_classe
     WHERE t.sa_classe_transiter   = :classe
       AND t.refer_annee_transiter = :annee
       AND n.refer_sequence        = :sequence
       AND n.valeur_note IS NOT NULL                    -- une note absente ne compte pas comme 0
     GROUP BY t.id, e.nom_eleve, e.prenom_eleve
)
SELECT eleve,
       round(points / coefficients, 2)                       AS moyenne,
       RANK() OVER (ORDER BY points / coefficients DESC)     AS rang,
       matieres_notees,
       round(avg(points / coefficients) OVER (), 2)          AS moyenne_classe
  FROM moyennes
 ORDER BY rang, eleve;


-- Élèves dont au moins une note manque pour la séquence (contrôle avant impression)
SELECT e.nom_eleve, e.prenom_eleve, m.nom_matiere
  FROM transition t
  JOIN eleve   e ON e.id = t.eleve_id
  JOIN matiere m ON m.refer_classe = t.sa_classe_transiter
 WHERE t.sa_classe_transiter   = :classe
   AND t.refer_annee_transiter = :annee
   AND NOT EXISTS (SELECT 1 FROM note n
                    WHERE n.refer_eleve = t.id AND n.refer_matiere = m.code_matiere
                      AND n.refer_sequence = :sequence AND n.valeur_note IS NOT NULL)
 ORDER BY e.nom_eleve, m.nom_matiere;


-- Vérifier que l'index composé est utilisé (Index Scan / Bitmap Index Scan attendu
-- sur fki_note_matiere plutôt qu'un Seq Scan dès que la table dépasse quelques milliers de lignes)
EXPLAIN (ANALYZE, BUFFERS)
SELECT n.refer_eleve, n.valeur_note
  FROM note n
 WHERE n.refer_matiere = 'MATH' AND n.refer_classe = :classe;
