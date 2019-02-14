# HyperNerd

[![Build Status](https://travis-ci.org/tsoding/HyperNerd.svg?branch=master)](https://travis-ci.org/tsoding/HyperNerd)
[![Good For Stream](https://img.shields.io/github/issues/tsoding/HyperNerd/good%20for%20stream.svg)](https://github.com/tsoding/hypernerd/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+for+stream%22)

![HyperNerd](https://i.imgur.com/07Ymbi6.png)

Second iteration of [Tsoder][tsoder]. Chat bot for [Tsoding][tsoding] streams.

## Quick Start

### NixOS

```console
$ nix-shell
$ cabal configure
$ cabal build
$ cabal test
$ cabal exec hlint .
$ cabal run secret.ini database.db
```

### Stack

Native dependencies:
- OpenSSL
- zlib

```console
$ stack build
$ stack exec hlint .
$ stack exec HyperNerd secret.ini database.db
```

### Example of a secret.ini file

The `secret.ini` file consist of a single section `Bot` the format of which depends on its `type`.

```ini
[Bot]
type = twitch|discord
...
... the rest of the parameters ...
...
```

#### Twitch Bot

```ini
[Bot]
type = twitch
nick = HyperNerd
owner = <your-name>
password = 12345
channel = Tsoding
clientId = <client-id-token>
database = twitch.db
```

| name       | description                                                                                                  |
|------------|--------------------------------------------------------------------------------------------------------------|
| `nick`     | Nickname of the bot.                                                                                         |
| `owner`    | Owner of the bot. The bot will recognize this name as an authority regardless of being a mod or broadcaster. |
| `password` | Password generated by https://twitchapps.com/tmi/.                                                           |
| `channel`  | Channel that the bot will join on start up.                                                                  |
| `clientId` | Client ID for Twitch API calls.                                                                              |

#### Discord Bot

```ini
[Bot]
type = discord
authToken = <auth-token>
guild = <guild-id>
channel = <channel-id>
```

| name        | description                                                                                                               |
|-------------|---------------------------------------------------------------------------------------------------------------------------|
| `authToken` | Authentication Token for the bot: https://github.com/reactiflux/discord-irc/wiki/Creating-a-discord-bot-&-getting-a-token |
| `guild`     | The id of the guild the bot listens to                                                                                    |
| `channel`   | The id of the channel the bot listens to                                                                                  |

## Markov Chain Responses

To trigger a Markov chain response, just mention the bot in the chat.

### Training the Markov Model

The Markov model is a csv file that is generated from the logs in the
bot's database file using the `Markov` CLI utility:

```console
$ cabal exec Markov database.db markov.csv
```

This command will produce the `markov.csv` file.

### Using the Trained Markov Model with the Bot

```console
$ cabal exec HyperNerd secret.ini database.db markov.csv
```

The `markov.csv` file is not automatically updated. To update the file
with the new logs you have to run the `Markov` CLI utility again.

## Command Aliases

You can assign a command alias to any command:

```
<user> !test
<bot> test
<user> !addalias foo test
<user> !foo
<bot> test
```

The aliases are "redirected" only one level deep meaning that transitive aliases are not supported:

```
<user> !addalias bar foo
<user> !bar
*nothing, because !bar is redirected to !foo, but further redirect from !foo to !test does not happen*
```

Motivation to not support transitive aliases is the following:
- They are not needed in most of the cases. Generally you just have a
  main command and a bunch of aliases to it.
- Support for transitive aliases requires to traverse and maintain a
  "tree" of aliases, which complicates the logic and degrades the
  performance.

## Quote Database

- `!addquote <quote-text>` -- Add a quote to the quote database. Available only to subs and mods.
- `!delquote <quote-id>` -- Delete quote by id. Available only to Tsoding.
- `!quote [quote-id]` -- Query quote from the quote database.

## Support

You can support my work via

- Twitch channel: https://www.twitch.tv/subs/tsoding
- Patreon: https://www.patreon.com/tsoding

[tsoder]: http://github.com/tsoding/tsoder
[tsoding]: https://www.twitch.tv/tsoding

<!-- TODO(#426): Markov feature is not documented -->
<!-- TODO(#427): Markov training is not automated -->
