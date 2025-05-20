# Release Creation process

## Build & Release

### Create a New Release

Only approvers in the [Networking area of the ARP working group](https://github.com/cloudfoundry/community/blob/main/toc/working-groups/app-runtime-platform.md#roles--technical-assets) can create new releases. 
First, a draft release is prepared via running some jobs in the [haproxy-boshrelease pipeline](https://concourse.arp.cloudfoundry.org/teams/main/pipelines/haproxy-boshrelease) of the community concourse.
Afterwards, the release notes are written and the draft release is finalized in the Github Web UI. 
Here are the detailed steps:

1. The version number is controlled by the concourse pipeline and can be automatically incremented via the `patch`, `minor` and `major` steps. Please refer to [Versioning Guide](https://github.com/cloudfoundry/haproxy-boshrelease/tree/master/ci#versioning-guide).
   Assuming the last release was `v11.12.3`, run one of the jobs:
   * `patch`, which will update the version resource in concourse to the next patch version (e.g. `v11.12.4`);
   * `minor`, which will update the version resource in concourse to the next minor version (e.g. `v11.13.0`);
   * `major`, which will update the version resource in concourse to the next major version (e.g. `v12.0.0`).

2. After configuring the version by running one of the three jobs, run the `rc` job. 
3. When all jobs have succeeded, trigger the `shipit` job to create a new draft release. 
4. Using the GitHub UI, finalise the release note and release: 
   * Use the "Generate Release Note" button to get a list of all changes. Remove all CI and test related commits as those don't impact the resulting release bundle. Retain information that changes the release itself (e.g. HAProxy version bumps).
   * Add information about noteworthy fixes, changes and features. Look at the overall changes list to ensure you didn't miss important changes by other committers. 
   * Add information about shipped version bumps in the "Upgrades" section (HAProxy, keepalived, etc.). The versions table is generated automatically and shows the versions contained in this release already.

   Once the release note text is complete, finalise the release via "Publish Release". Leave the "Set as the latest release" checkbox ticked. 


## Access to Concourse

ARP WG Concourse [repository](https://github.com/cloudfoundry/routing-concourse).

URL: [https://concourse.arp.cloudfoundry.org](https://concourse.arp.cloudfoundry.org)

Access: Follow instructions in [README.md](https://github.com/cloudfoundry/routing-concourse/blob/main/README.md#authentication-to-concourse)

**Note: This concourse is publicly visible**

By default, you will be able to view pipelines that are publicly visible.

If you are member of `wg-app-runtime-platform-networking-extensions-approvers` [group in cloudfoundry organization](https://github.com/orgs/cloudfoundry/teams/wg-app-runtime-platform-networking-extensions-approvers) in github, please log in using your git credentials and you will be able to manipulate the pipelines.

