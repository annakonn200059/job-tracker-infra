# Job Tracker — Infrastructure

Terraform, Ansible, Helm charts and Argo CD manifests for the job tracker,
plus the local development environment.

## Repository layout

All four repositories must sit side by side. The compose file references
siblings by relative path (`../../job-tracker-api`), so a different layout
breaks the build.

```
job-tracker/
├── job-tracker-web/       Next.js monorepo: apps/web, apps/landing
├── job-tracker-api/       Go REST API
├── job-tracker-worker/    Python worker
└── job-tracker-infra/     this repository
```

```bash
mkdir job-tracker && cd job-tracker
git clone git@github.com:annakonn200059/job-tracker-web.git
git clone git@github.com:annakonn200059/job-tracker-api.git
git clone git@github.com:annakonn200059/job-tracker-worker.git
git clone git@github.com:annakonn200059/job-tracker-infra.git
```

## Local environment

```bash
make up-db    # PostgreSQL only — for running services natively
make up       # everything, built from the sibling repositories
make ps
make logs
make psql
make down
make reset    # down -v && up-db: wipes the database
```

| Service | URL |
|---|---|
| web | http://localhost:3000 |
| landing | http://localhost:3001 |
| api | http://localhost:8080 |
| postgres | localhost:5432 |

Migrations live in `job-tracker-api` and are applied from there:

```bash
cd ../job-tracker-api && make migrate-up
```

> Compose is temporary. It goes away once the services run in a local
> Kubernetes cluster and the Helm chart becomes the single description of how
> they fit together.