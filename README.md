# Secure files

## Description

I've started this Bash script some days ago, in the aims to keep a list of my accounts and passwords on my computer without others being able to read it.

Actually, the script looks like an alias to various commands like `gpg`, `chattr`...
It's still in development, so I don't recommend running it since it may produce data loss.

## Features

Some basic features are available:

- Add/remove the 'immutable' attribute to a file (only on ext file systems)
- Edit a file with this attribute (same)
- Encrypt/decrypt files via [GnuPG](https://gnupg.org/)

## Dependencies

| Dependency                                                              | Why?                                             |
| ----------------------------------------------------------------------- | ------------------------------------------------ |
| e2fsprogs                                                               | For [un]setting the immutable attribute on files |
| A text editor that can be run as root (e.g. [Vim](https://www.vim.org/) | To edit files                                    |
| GnuPG                                                                   | To encrypt/decrypt files                         |

## Usage

To get the help message, call the script without arguments.

For example, if it is in the current directory:

```bash
./secure-file.sh
```

Note: this help message is a draft.

You must be root to use this script.

## To do

- [ ] Improve help messages
- [ ] Optimize
- [ ] Make it more secure (no data loss)
- [ ] Something to unsecure a file, execute a command on it, then resecure the file
- [ ] Improve code readability
- [ ] Executable as non-root user
- [ ] Support not only for ext file systems
