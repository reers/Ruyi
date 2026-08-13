# Publishing `io.github.reers:ruyi` to Maven Central

Repo wiring is done (`com.vanniktech.maven.publish` + POM + signing hooks).  
**Secrets never live in this repository** — only in `~/.gradle/gradle.properties` (or CI env).

Coordinates: **`io.github.reers:ruyi:<VERSION_NAME>`**  
Published file name: **`ruyi-<VERSION_NAME>.aar`**.

Depends on: `io.github.vnixx:thorvg` (already on Maven Central).

---

## Order of operations (do this once, then publish)

### 1. Register the Maven Central namespace

1. Sign in at [https://central.sonatype.com/](https://central.sonatype.com/) (same account used for `io.github.vnixx` is fine).
2. **Namespaces** → claim / verify **`io.github.reers`** (GitHub org namespace; follow verification).
3. Wait until the namespace shows as verified / ready.

> One Portal token + one GPG key can cover multiple namespaces on the same account.

### 2. Create a Portal user token

1. Central Portal → **Account** → **Generate User Token**.
2. Copy **Username** + **Password** (this is *not* your login password).
3. If lost: regenerate (old token dies). Safe to rotate anytime.

### 3. GPG signing key

Reuse the same GPG key already used for `io.github.vnixx:thorvg` if it is on a supported keyserver.  
Otherwise see the checklist in `thorvg.android` `PUBLISHING.md`.

### 4. Put secrets in `~/.gradle/gradle.properties`

```bash
mkdir -p ~/.gradle
# edit ~/.gradle/gradle.properties — template:
#   gradle/maven-publish.secrets.example
```

### 5. Confirm version in this repo

`gradle.properties` → `VERSION_NAME` (currently `1.0.2`).
Bump this for every new release. **Do not reuse a version that already exists on Central.**

### 6. Build & upload

```bash
cd Android/Ruyi
./gradlew :ruyi:assembleRelease          # sanity
./gradlew :ruyi:publishToMavenCentral    # upload + sign
```

### 7. Publish on the website

1. Open [Deployments](https://central.sonatype.com/publishing).
2. Wait until validation succeeds.
3. Click **Publish**.
4. Wait ~10–30+ minutes, then:

```kotlin
implementation("io.github.reers:ruyi:1.0.2")
```

---

## Optional / local-only

```bash
# Machine-local Maven cache (no Central)
./gradlew :ruyi:publishToMavenLocal

# Auto-publish after validation (skip manual website click)
# Uncomment in gradle.properties:
# mavenCentralAutomaticPublishing=true
# Then:
./gradlew :ruyi:publishAndReleaseToMavenCentral
```

---

## What is already done in-repo

| Item | Status |
|------|--------|
| `com.vanniktech.maven.publish` 0.34.0 | done |
| Central Portal target | done (`publishToMavenCentral()`) |
| GPG signing on publish | done (`signAllPublications`; needs your key) |
| POM / MIT / SCM / developer | done (`gradle.properties`) |
| Secrets template | done (`gradle/maven-publish.secrets.example`) |
| Namespace `io.github.reers` verified | **you** |
| First Central Publish click | **you** |
