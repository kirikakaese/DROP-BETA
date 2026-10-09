# Setting up sign-in with GitHub

This guide connects DROP to the GitHub OAuth App it signs in with, one step at a time. DROP uses
GitHub's **device flow**: it shows a short code, you approve it on github.com, and DROP keeps the
tokens in your Keychain. There is **no client secret** anywhere, on your Mac or in CI.

- **Part A** describes the OAuth App. It is **already done**; read it if you ever need to check or
  recreate the app.
- **Part B** is done **once per Mac** you build DROP on. It takes about 2 minutes.
- **Part C** is done **once** for CI and release builds. It is **already done** as well.

Each step ends with a **✅ Done when** line, so you know you can move on.

**Contents**

- [Before you start](#before-you-start)
- [Part A: The OAuth App (done)](#part-a-the-oauth-app-done)
- [Part B: Give your local builds the Client ID (once per Mac)](#part-b-give-your-local-builds-the-client-id-once-per-mac)
- [Part C: Give CI the Client ID (done)](#part-c-give-ci-the-client-id-done)
- [How DROP handles tokens](#how-drop-handles-tokens)
- [If something goes wrong](#if-something-goes-wrong)

---

## Before you start

You need:

- **Your local copy of the DROP repository**, the folder you build DROP from in Xcode.
- **A browser where you are signed in to GitHub** as `kirikakaese`.

---

## Part A: The OAuth App (done)

**Why:** GitHub only hands out tokens to a registered app. DROP's app is called **DROP** and lives
under your account.

### Step A1: Check the app's settings

Open [github.com/settings/developers](https://github.com/settings/developers) → **OAuth Apps** →
**DROP**. It should have:

| Setting | Value |
| --- | --- |
| Application name | DROP |
| Homepage URL | `https://github.com/kirikakaese/DROP-BETA` |
| Authorization callback URL | none needed (device flow doesn't redirect) |
| **Enable Device Flow** | ✔ on |
| **Expire user authorization tokens** | ✔ on |
| Client secrets | **none**. Don't create one; DROP never uses it. |

✅ **Done when** the page shows **Enable Device Flow** ticked and a **Client ID** near the top
(it looks like `Ov23li…`).

---

## Part B: Give your local builds the Client ID (once per Mac)

**Why:** a build without the Client ID runs fine but can't sign in; Settings → Account says so.

### Step B1: Create `Config/Local.xcconfig`

In Terminal, in your DROP folder:

```sh
cp -n Config/Local.xcconfig.example Config/Local.xcconfig
open -e Config/Local.xcconfig
```

`-n` keeps an existing file. Git ignores `Config/Local.xcconfig`, so it never ends up in a commit.

✅ **Done when** TextEdit shows the file with a `DROP_OAUTH_CLIENT_ID =` line.

### Step B2: Paste the Client ID

Copy the **Client ID** from Step A1 and put it after the `=`:

```
DROP_OAUTH_CLIENT_ID = Ov23liExampleClientID
```

Save and close the file. The Client ID is public: it names the app, not you, and gives no access
by itself.

✅ **Done when** the line holds your Client ID and nothing else.

### Step B3: Sign in

Run `xcodegen generate`, build and run DROP, then open **Settings → Account** and click
**Sign In with GitHub…**. DROP shows a code; click **Open GitHub**, paste the code (it is already
on your clipboard) and approve.

✅ **Done when** Settings → Account shows your avatar and `@kirikakaese`.

---

## Part C: Give CI the Client ID (done)

**Why:** CI and release builds don't have your `Config/Local.xcconfig`. They pass the Client ID to
`xcodebuild` from a repository **variable** (not a secret, because it isn't one).

### Step C1: Check the variable

Open the repository on GitHub → **Settings** → **Secrets and variables** → **Actions** →
**Variables**.

✅ **Done when** `DROP_OAUTH_CLIENT_ID` is listed with the same value as in Step A1. The CI job
**App build** checks that the built app contains it.

---

## How DROP handles tokens

- DROP asks for the **`repo`** scope: tags, GitHub Releases, assets and pull requests in public
  and private repositories. It asks for **`workflow`** only later, when you let it add a release
  workflow to a repository. Settings → Account explains both.
- The access token, the refresh token and both expiry times are stored **only in the Keychain**
  (login keychain, this Mac only, never synced). They never reach files, logs or the database.
- DROP refreshes the access token **5 minutes before it expires**, and once more if GitHub
  answers a request with 401.
- A refresh token works **only once**, so all refreshes go through one place: requests that need a
  new token while a refresh is running wait for it and use its result.
- When the refresh token has expired or was revoked, DROP shows **Sign In Again** instead of
  failing quietly.
- **Sign Out** deletes the tokens from the Keychain. To revoke DROP's access on GitHub as well, use
  [github.com/settings/applications](https://github.com/settings/applications) → **Authorized OAuth
  Apps** → **DROP** → **Revoke**.

---

## If something goes wrong

| What you see | What it means | What to do |
| --- | --- | --- |
| "This build has no GitHub Client ID" | `DROP_OAUTH_CLIENT_ID` is empty in this build. | Do Part B, then build again. |
| "GitHub doesn't know this build's Client ID" | The Client ID has a typo, or the app was deleted. | Copy it again from Step A1. |
| "Device flow is turned off for DROP's OAuth App" | **Enable Device Flow** is off. | Tick it in Step A1. |
| "The sign-in code expired before it was approved" | The code is valid for about 15 minutes. | Click **Sign In with GitHub…** again. |
| "Your GitHub session has ended" | The refresh token expired (after about 6 months without use) or was revoked. | Click **Sign In Again**. |
| macOS asks whether DROP may use its keychain item | The app's signature changed (for example after an update). | Enter your Mac password and click **Always Allow**. |
