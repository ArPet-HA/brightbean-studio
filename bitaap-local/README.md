# BitAap: lokale BrightBean-testopstelling

Deze map is een toevoeging van BitAap aan de BrightBean-fork. Daarmee draai je BrightBean
volledig lokaal (Docker) en kun je toch echt naar Facebook en Instagram publiceren.

**Productie draait op Railway + Cloudflare R2.** Deze opstelling is alleen voor testen,
bijvoorbeeld van een nieuwe BrightBean-versie of een wijziging in BitAap, zonder de
productieomgeving te raken.

## Waarom een tunnel?

Meta haalt afbeeldingen voor Facebook-foto's en Instagram op via een **publiek adres**
(`APP_URL/media/...`). `localhost` is voor Meta onbereikbaar. Het script start daarom:

- `bb-media`: een kleine server die **alleen** `/media/...` uit het BrightBean-mediavolume
  uitlevert (alleen-lezen, geen mappenoverzicht, geen toegang tot de rest van de app);
- `bb-media-tunnel`: een tijdelijke Cloudflare quick tunnel (`*.trycloudflare.com`, geen account nodig).

De BrightBean-app zelf blijft alleen bereikbaar op `http://localhost:8000`. Tunnel nooit de
hele app: die draait lokaal met `DEBUG=true`.

## Eenmalig voorbereiden

1. Docker Desktop installeren en starten.
2. In de BrightBean-map `.env.example` kopiëren naar `.env` en invullen:
   - `SECRET_KEY` en `ENCRYPTION_KEY_SALT`: willekeurige lange waarden;
   - `PLATFORM_FACEBOOK_APP_ID` en `PLATFORM_FACEBOOK_APP_SECRET`: uit Meta for Developers;
   - `DEBUG=true`, `ALLOWED_HOSTS=localhost,127.0.0.1`, `STORAGE_BACKEND=local`.
   - `APP_URL` hoef je niet te zetten: het script overschrijft die met het tunneladres.
3. In Meta for Developers → Facebook Login → *Valid OAuth Redirect URIs*:
   `http://localhost:8000/social-accounts/callback/facebook/` (en `/instagram/`).
4. Na de eerste start: `docker compose exec app python manage.py createsuperuser`.

## Starten en stoppen

- **Starten:** dubbelklik `bitaap-local\Start BrightBean + tunnel.cmd`. Het script:
  1. controleert Docker en `.env`, en bouwt het image als dat nog ontbreekt;
  2. start Postgres, de mediaserver en een nieuwe tunnel;
  3. zet `APP_URL` van app en worker op het tunneladres, via het gegenereerde
     `tunnel.override.yml` (staat niet in Git);
  4. controleert de API (`401` zonder key), de media via de tunnel en het `APP_URL` van de worker;
  5. start BitAap Growth OS als die in de map ernaast staat en nog niet draait.
- **Stoppen:** dubbelklik `bitaap-local\stop-brightbean-tunnel.cmd`. De data blijft bewaard in
  de Docker-volumes `brightbeanstudio_postgres_data` en `brightbeanstudio_media_data`.

Het tunneladres verandert bij elke start. Het script zet `APP_URL` steeds opnieuw.
Laat de computer aan tot ingeplande social posts zijn verstuurd: de worker draait lokaal.

## BitAap op de lokale BrightBean aansluiten

1. In `BitAap Growth OS\.env.local`: `BRIGHTBEAN_APP_URL=http://localhost:8000`, daarna BitAap herstarten.
2. In de lokale BrightBean (http://localhost:8000): accounts koppelen in de juiste workspace en onder
   *API keys* een key maken met de rechten `create_posts`, `upload_media` en `publish_directly`.
3. In BitAap: Integrations → BrightBean → key plakken → *Opnieuw controleren*.

Terug naar productie: `BRIGHTBEAN_APP_URL` weer op het Railway-adres zetten, BitAap herstarten en
de productie-key opnieuw invullen.

## Productie (Railway) in het kort

Voor als de Railway-omgeving opnieuw moet worden opgezet:

- Deploy vanaf deze fork (branch `main`), **niet** vanaf de Railway-template: die mist
  `ACCOUNT_ALLOW_SIGNUP`.
- Services: `web`, `worker`, Postgres, alle drie in EU West.
  - web, start command: `/bin/sh -c "gunicorn config.wsgi:application --bind 0.0.0.0:$PORT --workers 2 --threads 2"`.
    Zonder `/bin/sh -c` wordt `$PORT` uit de Procfile niet vervangen en crasht gunicorn.
  - web, pre-deploy: `python manage.py migrate --noinput`.
  - worker, start command: `python manage.py process_tasks`. Start de worker opnieuw als hij vóór
    de eerste migratie is gestopt.
  - Healthcheck `/health/` werkt pas als `healthcheck.railway.app` in `ALLOWED_HOSTS` staat.
- Variabelen, op web **en** worker:
  - `DJANGO_SETTINGS_MODULE=config.settings.production`
  - `SECRET_KEY`, `ENCRYPTION_KEY_SALT` (die laatste nooit meer wijzigen)
  - `DATABASE_URL=${{Postgres.DATABASE_URL}}`
  - `ALLOWED_HOSTS`, `APP_URL`
  - `ACCOUNT_ALLOW_SIGNUP=false`
  - `STORAGE_BACKEND=s3`, `S3_ENDPOINT_URL`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`,
    `S3_BUCKET_NAME`, `S3_REGION_NAME=auto`; laat `S3_CUSTOM_DOMAIN` leeg voor ondertekende links
  - `EMAIL_BACKEND_TYPE=console`
  - `PLATFORM_FACEBOOK_APP_ID`, `PLATFORM_FACEBOOK_APP_SECRET`
- R2-bucket privé houden. Het API-token krijgt *Object Read & Write*, alleen voor die bucket.
  CORS is niet nodig.
- Meta: het Railway-domein bij *App domains* en de callback-URL's bij *Valid OAuth Redirect URIs*.
- Eerste gebruiker: Railway → web → Console → `python manage.py createsuperuser`.
