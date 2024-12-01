# NAME

mii - Just a little test

# SYNOPSIS

mii \[command\] \[options\]

# Commands

```
mii [command] [optons]
```

## Commands

```
mint Module::Name [options]     mint a new distribution
help [command]                  brief help message
version                         display version information
dist                            build a dist
disttest                        build a dist and test it with cpanminus
release                         build a dist and (maybe) upload it to PAUSE
```

For more on each command, try 'mii help mint' or 'mii help help'

## mint

Mint a new distribution.

Examples:

```
mii mint Acme::Anvil --license=artistic_2
```

### Options

```
--author        your name and email address
--license       your software license(s) of choice (default is artistic_2)
```

## help

Print a brief help message and exits.

To get help with a specific command, try 'mii help mint'

## version

Prints version information and exits.

## dist

Build a dist. Most metadata (not including the changelog) is updated.

### Options

```
--verbose     be noisy
--trial       generate a TRIAL dist
```

## disttest

Build a dist and test it with cpanminus. Most metadata (not including the changelog) is updated.

### Options

```
--verbose     be noisy
```

## release

Build a dist and upload it to PAUSE. All metadata (including the changelog) is updated before release.

### Options

```
--verbose     be noisy
--pause       upload to PAUSE without prompting us
--trial       generate a TRIAL dist for PAUSE
```

# DESCRIPTION

**This program** will read the given input file(s) and do something useful with the contents thereof.
