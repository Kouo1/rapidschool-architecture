# RapidSchool : architecture et bases de données

Logiciel de gestion scolaire utilisé par des établissements secondaires au Cameroun :
inscriptions, notes, bulletins, absences, discipline, scolarité et emplois du temps.
Je l’ai conçu et développé, et je le maintiens depuis 2018.

Ce dépôt présente **l'architecture, le modèle de données et des scripts d'administration
PostgreSQL**. Le code source de l'application est privé (produit commercial) ; il peut être
présenté en entretien.

| | RapidSchool Desktop | RapidSchool web (SaaS) |
|---|---|---|
| Depuis | 2018 (version 7 en 2026) | 2025 |
| Technologies | Java 8 Swing, PostgreSQL 9 → 18 | Laravel, React/Vite, MySQL 8, Node.js/Puppeteer (AWS EC2) |
| Déploiement | Réseau local : un poste serveur, plusieurs postes clients | En ligne, multi-établissement |
| Base de données | Une base par année scolaire, 58 tables | Base partagée, isolation par établissement |
| Documentation | [desktop-postgresql.md](docs/desktop-postgresql.md) | [web-saas.md](docs/web-saas.md) |
| Liens | [Démo vidéo](https://youtu.be/veMwmsi3OCo) · [Téléchargement](https://github.com/Kouo1/rapidschool-desktop/releases/latest) | [rapidschool.cm](https://www.rapidschool.cm) |

## Contenu

| Fichier | Ce qu'il montre |
|---|---|
| [`sql/postgresql/01_schema_noyau.sql`](sql/postgresql/01_schema_noyau.sql) | Noyau du modèle relationnel : clés techniques, clés étrangères composées, contraintes `CHECK`, index de jointure |
| [`sql/postgresql/02_migration_matricule_vers_id.sql`](sql/postgresql/02_migration_matricule_vers_id.sql) | Migration de production d'une clé naturelle (texte) vers une clé technique : transaction unique, verrou, mise de côté des orphelins, **contrôle par empreinte MD5 avant/après** |
| [`sql/postgresql/03_requetes_bulletin.sql`](sql/postgresql/03_requetes_bulletin.sql) | Moyenne pondérée et rang en une requête (`RANK() OVER`), contrôle des notes manquantes, `EXPLAIN (ANALYZE, BUFFERS)` |
| [`sql/postgresql/04_roles_moindre_privilege.sql`](sql/postgresql/04_roles_moindre_privilege.sql) | Rôles séparés (propriétaire, application, lecture, sauvegarde), `REVOKE` sur `PUBLIC`, privilèges par défaut |
| [`scripts/Sauvegarde-BaseAnnee.ps1`](scripts/Sauvegarde-BaseAnnee.ps1) | Sauvegarde `pg_dump` vérifiée par `pg_restore --list`, empreinte SHA-256, rotation, journal, codes de sortie pour le Planificateur de tâches |
| [`tests/`](tests/) | Jeu d'essai au format V6 et script qui rejoue la migration de bout en bout |

## Essayer

```bash
# PostgreSQL local ou conteneur
docker run -d --name pg -e POSTGRES_PASSWORD=essai -p 5432:5432 postgres:16
export PGHOST=localhost PGUSER=postgres PGPASSWORD=essai
./tests/verifier.sh
```

Résultat attendu : la migration affiche `Contrôle OK` pour chaque table, une ligne orpheline
est mise de côté, un matricule est corrigé sans perdre ses notes, puis le bulletin est calculé.

## Quelques chiffres

- Application desktop : environ 550 fichiers Java, près de 300 000 lignes ; installateurs Windows 32 et 64 bits avec Java et PostgreSQL embarqués.
- Migration V6 → V7 validée en comparant les résultats de l'ancien et du nouveau code sur des bases réelles de plusieurs années.
- API web : environ 280 routes, plus de 70 migrations versionnées.

---
Sylvain KOUO PEHUIE · Les données des exemples sont fictives.
