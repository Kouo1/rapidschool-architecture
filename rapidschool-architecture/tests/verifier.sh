#!/usr/bin/env bash
# Rejoue la migration V6 -> V7 sur le jeu d'essai, puis vérifie le schéma V7 et les requêtes.
# Prérequis : psql et un serveur PostgreSQL accessible (variables PGHOST, PGPORT, PGUSER).
# Usage : ./tests/verifier.sh
set -euo pipefail
cd "$(dirname "$0")/.."
PSQL="psql -X -q -v ON_ERROR_STOP=1"

for base in rs_demo_v6 rs_demo_v7; do dropdb --if-exists "$base"; createdb "$base"; done

echo "== Migration V6 -> V7 (jeu d'essai)"
$PSQL -d rs_demo_v6 -f tests/jeu_demo_ancien_format.sql
$PSQL -d rs_demo_v6 -f sql/postgresql/02_migration_matricule_vers_id.sql
$PSQL -d rs_demo_v6 -c "SELECT count(*) AS orphelins_mis_de_cote FROM rs_conv_orphelins_absence"

echo "== Le matricule est maintenant modifiable sans casser les notes"
$PSQL -d rs_demo_v6 -c "UPDATE eleve SET matricule_eleve = '24A001-CORRIGE' WHERE matricule_eleve = '24A001';
                        UPDATE transition SET matricule_transiter = '24A001-CORRIGE' WHERE matricule_transiter = '24A001';
                        SELECT t.matricule_transiter, count(n.*) AS notes
                          FROM transition t LEFT JOIN note n ON n.refer_eleve = t.id
                         GROUP BY t.matricule_transiter ORDER BY 1;"

echo "== Schéma V7 et requêtes de bulletin"
$PSQL -d rs_demo_v7 -f sql/postgresql/01_schema_noyau.sql
$PSQL -d rs_demo_v6 -v classe="'6E-A'" -v sequence="'1'" -v annee="'2024/2025'" \
      -f sql/postgresql/03_requetes_bulletin.sql

for base in rs_demo_v6 rs_demo_v7; do dropdb "$base"; done
echo "== Tout est passé."
