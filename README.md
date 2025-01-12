# Caravel User Project

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0) [![UPRJ_CI](https://github.com/efabless/caravel_project_example/actions/workflows/user_project_ci.yml/badge.svg)](https://github.com/efabless/caravel_project_example/actions/workflows/user_project_ci.yml) [![Caravel Build](https://github.com/efabless/caravel_project_example/actions/workflows/caravel_build.yml/badge.svg)](https://github.com/efabless/caravel_project_example/actions/workflows/caravel_build.yml)


# SHA-1 engine

See a [https://github.com/konradwilk/sha1](https://github.com/konradwilk/sha1) for the full git history of this code. Branch name is submission-mpw-two.

This is an implementation of [https://www.rfc-editor.org/rfc/inline-errata/rfc3174.html](RFC 3174) of SHA-1 engine.

It is not the most secure one nowadays (it is still used for git commit ids and TPM PCR values), but
it looked like the easiest of the SHA engines to implement. The communication channel is via
WishBone commands to provide sixteen words after which the engine starts and computes the digest
in about 160 cycles. Then digest can be retrieved via the wishbone. There is a IRQ line so when
it has completed it will bring it high if that is enabled.

![SHA1](pics/sha1.png)


# Documentation for building

## Setup

To create the GDS files, there are macros that are being ingested. The best way to do is by
checking out the SHA-1 engine [https://github.com/konradwilk/sha1](https://github.com/konradwilk/sha1):

```
git clone https://github.com/konradwilk/sha1
```

And then there are some pre-requisities:

 - You need to have OpenLANE installed. The Makefile assumes that is all setup.
   Specifically that the docker container is installed.
 - And make sure to have TARGET_PATH set to this directory (caravel_user_project).
 - You have the `open_mpw_checker` installed as well (and the docker container).

From within the `sha1` directory execute:

# Creating of GDS

```
make gds
```

which after running tests will generate the GDS, LEF, etc files. It will also copy
them in the `gds` sub-directory.  Those files should then be in caravel_user_project, which
can either be done manually, or with automatic way. To do that:

```
make caravel
```

which will copy the appropiate files, run the OpenLANE to create the user_project_wrapper macro
together, and run the checkers.


# To understand the code

The best way is to look at the test-cases and run them:

```
make test_wb_logic
```

which will use the various WishBone commands to program it.

