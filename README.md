# Secure files

**PLEASE _DO NOT_ USE THIS SCRIPT**
**IT WAS WRITTEN A LONG TIME AGO AND IT IS _NOT_ SECURE AT ALL**

## Description

Before I start writing this script, I wanted to store my passwords in a secure way on my computer.
I learned about the immutable attribute and [GnuPG](https://gnupg.org) and it was great, but I was thinking I add to enter to much commands.
So began this script, in the aim to automate this task.

## Features

- Only on ext file systems and requires the script to be run as root:
    add/remove the 'immutable' attribute to a file,
    edit a file with this attribute
- Encrypt/decrypt files via [GnuPG](https://gnupg.org/)
- Set the owner, group and mode of a file

## Dependencies

| Dependency                                                               | Why?                                        |
| ------------------------------------------------------------------------ | ------------------------------------------- |
| [bash](https://www.gnu.org/software/bash)                                | To run the script                           |
| e2fsprogs                                                                | To [un]set the immutable attribute on files |
| A text editor that can be run as root (e.g. [Vim](https://www.vim.org/)) | To edit files                               |
| [GnuPG](https://gnupg.org/)                                              | To encrypt/decrypt files                    |

## Usage

To get the help message, call the script without arguments.

For example, if it is in the current directory:

```bash
./secure-file.sh
```

## To do

- [ ] Improve help messages
- [ ] Make it more secure (no data loss)
- [ ] Something to unsecure a file, execute a command on it, then resecure the file
- [ ] Improve code readability
- [ ] Executable as non-root user
- [ ] Support not only for ext file systems
