# Overview

This Energy Savings Program application project is a clone of the BC Housing Permit Portal.

## Getting Started

The codebase uses Rails on the back-end, and React/MST stack on the front-end.

Ensure you have the following:

- Ruby 3.2.2
- Postgres 13+
- Redis
- Node 20.10+

(Alternatively run this locally with `docker compose` see section further down)

**Please enable git LFS in order to properly clone the repo.**

## Running the application locally with Docker Compose

To make things easier to develop on various platforms locally, there is a `docker compose` script for the app that can be run. This will setup all critical dependencies locally and bring the app up mounted to your filesystem for live development. There are a few caveats to this to note which will are mentioned at the end of this section

**Prerequisites**

- Download and install Docker Desktop for your system
- Make sure that you can run both `docker` and `docker compose` in your terminal and this is working correctly
- Since some prefer to run this locally without Docker (see section below) this setup is aimed to preserve the ability to run this application both ways. As such, this uses a separate `Dockerfile.dev` and ENV file `.env.docker_compose` that we will use for the purposes of running locally only
- Ensure that you have a local copy of `.env.docker_compose` - an example is provided in `.env_example.docker_compose` which provides the minimal ENV configuration to start the app without some services (see first point in Caveats section for more info)
- We currently ONLY allow keycloak login have removed the ability to login via e-mail. To ensure you can login to the app make sure you have a valid Keycloak development ENV secrets set up so that you can properly log in. (See `.env_example.docker_compose` and [What is Keycloak at BC Government](https://developer.gov.bc.ca/docs/default/component/css-docs/What-is-Keycloak-at-BC-Government/))

**Instructions**

1. Clone this repo with git to your local machine
2. Run: `docker compose up` (this will start up all related services including Vite for HMR)
3. (If this is the first run of the application, create the database) `docker compose exec app bundle exec rails db:create`
4. (If this is the first run of the application OR if there are new migrations to run) Run migrations: `docker compose exec app bundle exec rails db:migrate`
5. (If this is the first run of the app or seeds have changed, you can rerun the seeder). Generate seed data: `docker compose exec app bundle exec rails db:seed`
6. Things should now be running. You can isolate / look at logs for various containers using `docker compose logs -f app` for example for the app logs (or any other service)
7. The app should reflect changes live if you edit the files in the folder (both Ruby and JS) since its mounted live on the filesystem
8. If you want to run a `binding.pry` or `debugger` you can do so in the code, and then run `docker compose attach app` to interact with the debugging interface.

**NOTES / Caveats**

- A minimal set of ENV vars that reference various services (eg. Redis, Postgres, etc.) are defaulted in the `docker-compose.yml` for dev purposes, the app also loads other ENV vars from `.env.docker_compose` so ensure that you have those setup if you are trying to use functionality related to that (eg. CHES keys for email sending, BCEID / keycloak stuff, etc.)
- Local development (see above) uses `letter_opener` / `launchy` to view emails locally. These do not work within the dockerized environment, and we haven't yet put in a workaround for this
- This local dockerized version does not contain a service for `Consigno Verifio Notarius Server` which is proprietary licensed software that helps with validating PDFs. Therefore all functionality around this will not work. You can either run the service manually outside Docker and refer to it using the ENV vars, or find a private repository that has the image that you can then run in `docker-compose`
- The local dockerized version does not setup Minio (which can be used to locally to mock Object Storage as it is S3 compatible - see instructions for local setup below). You can set this up manually outside the docker setup or add your own docker compose service for it. Just hook it up via the ENV vars (see `.env.example`) or simply switch the app to use actual `BCGOV_OBJECT_STORAGE` if you have a bucket allocation already.

## Running the application locally (non-dockerized)

- Install Dependencies: `bundle install` and `npm install`
- Ensure you have a `.env` file with required variables (reference `.env.example`)
- Set up Database credentials following [the official Rails guide](https://guides.rubyonrails.org/v2.3/getting_started.html#configuring-a-database). One of the ways is to have an environment variable called `DATABASE_URL`
- (_Only first time_) Create a database: `rails db:create`
- (_Only first time or if there are changes_) Run migrations: `rails db:migrate`
- (_Only first time or if there are changes_) Generate seed data: `rails db:seed`
- Start the server: `rails s`
- Start the front-end dev server for hot-reloading: `npm run dev`

### Workers (Sidekiq)

The app uses the [Sidekiq](https://github.com/sidekiq/sidekiq) library for background job processing. To run this locally:

- Ensure you have `Redis` installed locally
- Set ENV var `REDIS_URL=localhost:6379/0`
- Run `bundle exec sidekiq` (add a `-q queue_name`) to start that particular queue, you can see which queues are currently in the app in `config/initializers/sidekiq.rb` under `config.queues`

Recommended queue split for claims pipeline debugging:

- General worker: `SIDEKIQ_CONCURRENCY=10 bundle exec sidekiq -q default -q virus_scan -q file_processing -q webhooks -q websocket -q model_callbacks`
- Claims worker: `SIDEKIQ_CONCURRENCY=1 bundle exec sidekiq -q claims_ocr -q claims_genai`

* Note that the Openshift deployed versions make use of HA-Redis via Sentinels so the environment variables required for that are different

### Websockets (Anycable)

The app uses [Anycable](https://anycable.io/) to serve websockets in a scalable way. To run the websocket server locally:

- Ensure to `bundle install`
- [Download the `anycable-go` websocket server on OSX: `brew install anycable-go`](https://docs.anycable.io/anycable-go/getting_started)
- Add an ENV var `ANYCABLE_REDIS_URL=redis://localhost:6379/2`. It is recommended to set this value to a different Redis db than Sidekiq.

After installation run both the `anycable-go` websocket server as well as the RPC server

- RPC Server: `bundle exec anycable`
- Anycable-Go Sockets: `anycable-go --port=8080`

### Notorius - Digital Seal Validation

- For local development, ensure you have the right test endpoint. The dev / test / production environments are set up with a licensed version running in its own container.

### Local - File storage setup

- For the local environment, if you want to test the full file upload process, you would want to run a local version of minio to simulate the object storage environment.
- Install minio:

```
brew install minio

minio server --address 127.0.0.1:9001 ~/Documents/whatever-your-folder-for-storage-is
```

- Log into minio with the admin/password provided and set up the environment.
- Set up a bucket (in our example we call it `hous-local`)
  <img width="1466" alt="minio-create-bucket" src="https://github.com/bcgov/HOUS-permit-portal/assets/607956/81c315a5-1bc9-46c7-ac32-202269691276">
- Set up a user (in our example, we call it `hous-formio-user`)
  <img width="1458" alt="minio-create-user" src="https://github.com/bcgov/HOUS-permit-portal/assets/607956/0bc1864e-f461-4ad7-bfe0-4a76babb311e">
- Set up a policy (in our example, we call it `formioupload`)
  <img width="1462" alt="minio-create-policy" src="https://github.com/bcgov/HOUS-permit-portal/assets/607956/01890f09-633e-4dff-8e00-24d9fbb4494c">

```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "ListBucket",
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::hous-local"
            ]
        },
        {
            "Sid": "UploadFile",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:ListMultipartUploadParts",
                "s3:PutObject",
                "s3:AbortMultipartUpload",
                "s3:DeleteObject"
            ],
            "Resource": [
                "arn:aws:s3:::hous-local/*"
            ]
        },
        {
            "Sid": "crossdomainAccess",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject"
            ],
            "Resource": [
                "arn:aws:s3:::hous-local/crossdomain.xml"
            ]
        }
    ]
}
```

- note that "s3:PutObjectAcl" is ignored at the moment since we are at the root bucket, but we may need it later

- Assign the policy to the user
  <img width="1464" alt="minio-assign-policy" src="https://github.com/bcgov/HOUS-permit-portal/assets/607956/86f6b0c3-8c7f-43f7-afd7-fe2c4dce6dc4">
- You will need to add the following to your .env files:

```
BCGOV_OBJECT_STORAGE_ENDPOINT=http://127.0.0.1:9001
BCGOV_OBJECT_STORAGE_BUCKET=your-local-bucket-name
BCGOV_OBJECT_STORAGE_ACCESS_KEY_ID=your-local-user-access-key
BCGOV_OBJECT_STORAGE_SECRET_ACCESS_KEY=your-local-user-secret-access
BCGOV_OBJECT_STORAGE_REGION=us-east-1
```

The bucket path convention used is: `:bucket_name/permit-applications/:id/*`

---

## Background Jobs

Sidekiq is the background job processor, backed by Redis. Jobs are defined under [app/jobs](app/jobs).

Recurring/scheduled jobs are defined in [config/sidekiq_cron_schedule.yml](config/sidekiq_cron_schedule.yml) and managed by `sidekiq-cron`.

Notable job categories:

- **Virus scan callbacks** – ClamAV results trigger document status updates
- **Email dispatch** – Asynchronous delivery via CHES
- **Requirement template sync** – Propagating template structure changes across environments (see [docs/requirement-template-sync.md](docs/requirement-template-sync.md))

> **Note:** Redis serves 5 separate logical databases, each with its own ENV var: Sidekiq (`REDIS_URL`), AnyCable (`ANYCABLE_REDIS_URL`), rate limiting (`RATE_LIMIT_DEV_REDIS_URL`), activity feed (`SIMPLE_FEED_DEV_REDIS_URL`), and Rails cache (`CACHE_DEV_REDIS_URL`). Production environments use HA Redis via Sentinels — the required ENV vars differ from the simple `REDIS_URL` used locally.

---

## Real-Time (AnyCable)

The application uses [AnyCable](https://anycable.io/) for scalable WebSocket support, replacing ActionCable's default Ruby WebSocket handling.

- **`anycable-go`** — a standalone Go binary that handles WebSocket connections at scale, bundled at [bin/anycable-go](bin/anycable-go).
- **AnyCable RPC** — a Rails process exposing channel logic over gRPC, which `anycable-go` calls for connect/subscribe/message handling.

Configuration: [config/anycable.yml](config/anycable.yml), [config/cable.yml](config/cable.yml).

In development, both processes are started via Docker Compose. It is recommended to use a separate Redis DB for AnyCable (e.g. `ANYCABLE_REDIS_URL=redis://localhost:6379/2`) to avoid interference with Sidekiq queues.

---

## Search (Elasticsearch)

Full-text and filtered search is powered by Elasticsearch via the [Searchkick](https://github.com/ankane/searchkick) gem. Models that support search (applications, users, contractors, requirement blocks, templates, jurisdictions, etc.) define `searchkick` in their model and are indexed in Elasticsearch.

In development, Elasticsearch runs as a Docker Compose service on port `9200`. The `ELASTICSEARCH_URL` env var controls the connection.

---

## File Uploads & Virus Scanning

Files are uploaded via Shrine 3.5.0 (see [app/uploaders](app/uploaders)). All uploaded files are queued for virus scanning by ClamAV before they are made available.

The scan flow:

1. File is uploaded and stored with a `pending` scan status.
2. A background job submits the file to ClamAV.
3. ClamAV result triggers a callback that updates the document's scan status (`clean` / `infected`).
4. Infected files are quarantined and never surfaced to users.

See [docs/file-upload-flow.md](docs/file-upload-flow.md) and [docs/virus-scanning-update-flow.md](docs/virus-scanning-update-flow.md) for complete flow documentation.

---

## Email

Outbound email is delivered via the **BC Common Hosted Email Service (CHES)**. A custom delivery adapter is implemented in [lib/ches_email_delivery.rb](lib/ches_email_delivery.rb). Mailers are under [app/mailers](app/mailers).

Email delivery is always performed asynchronously via Sidekiq. In development, `letter_opener` is used to preview emails in the browser at `http://localhost:3000/letter_opener`.

---

## Testing

The test suite uses RSpec. Run it with:

```bash
bundle exec rspec
```

Configuration is in [.rspec](.rspec). Factories, support files, and shared examples live under `spec/`.

To generate an up-to-date ERD diagram (requires Graphviz):

```bash
bundle exec erd
```

---

## Formatting & Linting

- **Backend:** RuboCop ([.rubocop.yml](.rubocop.yml)) for linting; Ruby LSP for formatting. Install the RubyLSP VS Code extension and select it as the formatter.
- **Frontend:** Prettier ([.prettierrc.mjs](.prettierrc.mjs)) and ESLint ([.eslintrc](.eslintrc)).
- Pre-commit hooks are enforced via Husky ([.husky](.husky/)).

---

## Helm & Deployment

The application is deployed to OpenShift using Helm v3 in an **umbrella chart** pattern.

### Chart Structure

```
helm/
├── main/               ← Umbrella chart (aggregates all sub-charts)
│   ├── Chart.yaml
│   └── values.yaml     ← Environment-specific overrides go here
├── _app/               ← Rails application sub-chart
├── _sidekiq/           ← Sidekiq worker sub-chart
├── _anycable-rpc/      ← AnyCable RPC sub-chart
├── _clamav/            ← ClamAV sub-chart
└── _maintenance/       ← Maintenance pod sub-chart
```

Each sub-chart is prefixed with `_` to indicate it is a dependency of the umbrella `main` chart and not deployed independently.

### Secrets Management

Production secrets are managed via **Vault** (`global.vault` in helm values). Developers working on deployments or environment configuration should refer to the team's Vault setup for the appropriate secret paths and access policies.

### Deploying

Deployments are managed through GitHub Actions workflows under [.github/workflows](.github/workflows).

Environment-specific values (image tags, replica counts, resource limits, ingress hostnames) are supplied as `values.yaml` overrides in `helm/main/`.

For OpenShift-specific notes and legacy template history, see [openshift/Readme.md](openshift/Readme.md) and [devops/README.md](devops/README.md).

---

## Release Workflow

- **Regular releases:** Branching and tagging workflow described in [docs/test-and-prod-release-workflow.md](docs/test-and-prod-release-workflow.md).
- **Hotfixes:** Process documented in [docs/hotfix-branch-tag-workflow.md](docs/hotfix-branch-tag-workflow.md).
- Release versions are tracked in [VERSION](VERSION) and managed by `release-it` ([.release-it.json](.release-it.json)).

---

## AWS Credential Rotation

AWS S3 credentials are rotated automatically by Lambda every 2 days and synced to the database via Sidekiq. If OpenShift goes down during a rotation window, credentials can become stale and file uploads will fail.

For the full rotation procedure and automated script, see [docs/aws-credential-refresh.md](docs/aws-credential-refresh.md).

**Quick fix:**

```bash
./scripts/aws-credential-refresh.sh <env> "<access_key_id>" "<secret_access_key>"
```

---

## Additional Documentation

| Document                                                                         | Description                      |
| -------------------------------------------------------------------------------- | -------------------------------- |
| [docs/system-architecture-diagram.md](docs/system-architecture-diagram.md)       | System architecture overview     |
| [docs/file-upload-flow.md](docs/file-upload-flow.md)                             | File upload and storage flow     |
| [docs/virus-scanning-update-flow.md](docs/virus-scanning-update-flow.md)         | ClamAV scan lifecycle            |
| [docs/requirement-template-sync.md](docs/requirement-template-sync.md)           | Requirement template sync design |
| [docs/database-restore.md](docs/database-restore.md)                             | Database restore procedures      |
| [docs/test-and-prod-release-workflow.md](docs/test-and-prod-release-workflow.md) | Release process                  |
| [docs/hotfix-branch-tag-workflow.md](docs/hotfix-branch-tag-workflow.md)         | Hotfix process                   |
| [devops/README.md](devops/README.md)                                             | DevOps and infrastructure notes  |
| [docs/aws-credential-refresh.md](docs/aws-credential-refresh.md)                 | AWS S3 credential rotation       |

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

---

## License

See [LICENSE](LICENSE).
