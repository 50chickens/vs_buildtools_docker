# Infrastructure Design: SQL Server, SSIS and SSRS Hosting on AWS

Template, 17 November 2026. Fill in every \[bracketed\] value. Each section has a diagram placeholder that shows how the pieces connect.

## 1. Purpose and scope

- **Purpose:** Describe how SQL Server, SSIS and SSRS are hosted on AWS, and how the hosts are rebuilt automatically.
- **In scope:** Compute, storage, clustering, identity, certificates, DNS, SSIS and SSRS hosting, rebuild automation, local test pipeline.
- **Out of scope:** \[Application design, network CIDR planning, firewall rule detail\]
- **Owner:** \[name\]  **Reviewers:** \[names\]  **Version:** \[0.1\]

## 2. Environments and naming

The same design is repeated for each environment.

| Environment | AWS account | Region | Cluster name | Node 1 | Node 2 | RDS endpoint | FSx alias |
| --- | --- | --- | --- | --- | --- | --- | --- |
| A | \[ \] | \[ \] | CLUS-A | SQL-A1 | SQL-A2 | \[ \] | \[ \] |
| B | \[ \] | \[ \] | CLUS-B | SQL-B1 | SQL-B2 | \[ \] | \[ \] |
| C | \[ \] | \[ \] | CLUS-C | SQL-C1 | SQL-C2 | \[ \] | \[ \] |
| D | \[ \] | \[ \] | CLUS-D | SQL-D1 | SQL-D2 | \[ \] | \[ \] |

Naming standard: \[pattern for hosts, volumes, security groups, secrets, tags\]

## 3. Architecture overview

**Diagram 1: Overall architecture.** Shows users and schedulers, load balancer, SSRS hosts, SSIS hosts, SQL cluster, RDS, FSx, Active Directory, Secrets Manager, S3.

&#91;embedded content: overall architecture · 9 components\]

Users reach SSRS through the load balancer, the schedule starts the SSIS runs, both hosts use RDS, and FSx holds the shared packages, logs and cluster witness.

| Component | Purpose | Count per environment | Notes |
| --- | --- | --- | --- |
| SQL Server cluster nodes | \[Application databases\] | 2 | \[ \] |
| SSRS/SSIS host | \[Reports and package execution\] | \[ \] | \[Autoscaled or fixed\] |
| RDS for SQL Server | \[Target database platform\] | \[ \] | \[Edition, Multi-AZ\] |
| FSx for Windows | \[Shared packages, logs, witness\] | \[ \] | \[ \] |
| Application Load Balancer | \[SSRS front end\] | \[ \] | \[ \] |
| Active Directory | \[Identity, Kerberos\] | \[ \] | \[Managed AD or self-managed\] |

## 4. Compute

| Role | Instance type | vCPU | Memory | OS and edition | AMI ID | EBS-optimized | Placement |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SQL cluster node | \[ \] | \[ \] | \[ \] | \[ \] | \[ \] | \[ \] | \[AZ, placement group\] |
| SSRS host | \[ \] | \[ \] | \[ \] | \[ \] | \[ \] | \[ \] | \[ \] |
| SSIS host | \[ \] | \[ \] | \[ \] | \[ \] | \[ \] | \[ \] | \[ \] |

## 5. Storage and volumes

**Diagram 2: Storage layout.** Shows each host's EBS volumes and mount points, plus the FSx share used by SSIS, the cluster witness and backups.

&#91;embedded content: storage layout · 3 groups\]

SQL nodes keep data, log, TempDB and backup on separate EBS volumes; the SSIS host reads packages and writes logs on FSx, which also holds backups and the witness.

| Host role | Volume purpose | Drive or mount | Type | Size | IOPS | Throughput | Allocation unit | Encryption key |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SQL node | OS | C: | \[ \] | \[ \] | \[ \] | \[ \] | 4 KB | \[ \] |
| SQL node | Data | \[ \] | \[ \] | \[ \] | \[ \] | \[ \] | 64 KB | \[ \] |
| SQL node | Log | \[ \] | \[ \] | \[ \] | \[ \] | \[ \] | 64 KB | \[ \] |
| SQL node | TempDB | \[ \] | \[ \] | \[ \] | \[ \] | \[ \] | 64 KB | \[ \] |
| SQL node | Backup | \[ \] | \[ \] | \[ \] | \[ \] | \[ \] | 64 KB | \[ \] |
| SSRS/SSIS host | OS | C: | \[ \] | \[ \] | \[ \] | \[ \] | 4 KB | \[ \] |
| SSRS/SSIS host | Working and temp | \[ \] | \[ \] | \[ \] | \[ \] | \[ \] | \[ \] | \[ \] |

### FSx for Windows File Server

| Item | Value |
| --- | --- |
| File system ID and deployment type (single or multi-AZ) | \[ \] |
| Capacity and throughput | \[ \] |
| DNS alias | \[ \] |
| Shares | \[Packages, logs, backups, witness\] |
| Backup and retention | \[ \] |

## 6. SQL Server cluster

**Diagram 3: Cluster and availability design.** Shows two nodes, the cluster name object, the listener, replication or shared storage, and the file share witness.

&#91;embedded content: cluster design · 2 nodes, 1 witness\]

Clients connect to the listener or cluster name, which points at whichever node is active; both nodes also vote with the file share witness.

| Item | Value |
| --- | --- |
| Design | \[Failover cluster instance or availability group\] |
| Nodes and AZs | \[ \] |
| Quorum model and witness | \[File share witness on FSx\] |
| Cluster IPs (per subnet) | \[ \] |
| Listener name and port | \[ \] |
| Synchronous or asynchronous commit | \[ \] |
| Failover mode and tested RTO/RPO | \[ \] |
| SQL edition and version | \[ \] |
| Instance name, static port, collation | \[ \] |
| Max memory, MAXDOP, trace flags | \[ \] |
| TempDB layout | \[ \] |

## 7. RDS for SQL Server (target state)

| Item | Value |
| --- | --- |
| Engine and version | \[ \] |
| Instance class and storage | \[ \] |
| Multi-AZ | \[ \] |
| Databases hosted | \[Application databases, SSISDB, ReportServer, ReportServerTempDB\] |
| Parameter and option groups | \[ \] |
| Migration method and cutover plan | \[ \] |
| Limits that affect the design | \[SQL Agent cannot run PowerShell or command-line steps\] |

## 8. SSIS hosting

**Diagram 4: SSIS execution flow.** Shows the trigger, the host, the PowerShell wrapper, dtexec, the package source on the UNC share, the target databases and the log destination.

&#91;embedded content: SSIS execution flow · 5 steps\]

The trigger calls a PowerShell wrapper, which starts dtexec; dtexec loads the package from the UNC share, writes to the target databases and writes its log back to the share.

| Item | Value |
| --- | --- |
| Trigger mechanism | \[SQL Agent, Task Scheduler, EventBridge with SSM, other\] |
| Execution account | \[ \] |
| Package location (UNC) | \[ \] |
| Log location (UNC) | \[ \] |
| Package deployment model | \[File system or SSISDB catalog\] |
| 32-bit and 64-bit drivers, ODBC DSNs, OLE DB providers | \[ \] |
| Custom components and GAC items | \[ \] |
| Environment variables and parameters | \[ \] |
| Behavior during failover | \[Packages and logs remain reachable at the same UNC path\] |
| Log retention and cleanup | \[ \] |

## 9. SSRS hosting

**Diagram 5: SSRS request flow.** Shows the user, load balancer, SSRS host, ReportServer database, data sources and the encryption key store.

&#91;embedded content: SSRS request flow · 7 components\]

Users reach the SSRS host through the load balancer; the host reads its ReportServer database, needs the encryption key restored, and queries the report data sources.

| Item | Value |
| --- | --- |
| SSRS mode and version | \[Native\] |
| ReportServer and TempDB database location | \[ \] |
| Service account | \[ \] |
| URL reservations and portal URL | \[ \] |
| Load balancer and health check | \[ \] |
| Encryption key backup location and restore step | \[ \] |
| Shared data source credentials | \[ \] |
| SMTP and subscriptions | \[ \] |
| Configuration files to manage | \[rsreportserver.config, others\] |

## 10. Identity and Kerberos

**Diagram 6: Authentication and delegation.** Shows the user, SSRS, SQL Server and the file share, with the Kerberos tickets and delegation hops.

&#91;embedded content: Kerberos hops · 4 services\]

A user signs in to SSRS, and SSRS passes that identity on to SQL Server and the file share, so each service needs its own SPN and SSRS needs constrained delegation to both.

### Service accounts

| Service | Host role | Account (gMSA or standard) | Rights required | Password or secret store |
| --- | --- | --- | --- | --- |
| SQL Server engine | SQL node | \[ \] | \[Perform volume maintenance, Lock pages in memory\] | \[ \] |
| SQL Server Agent | SQL node | \[ \] | \[Log on as a service\] | \[ \] |
| SSRS | SSRS host | \[ \] | \[ \] | \[ \] |
| SSIS / dtexec execution | SSIS host | \[ \] | \[Read packages, write logs\] | \[ \] |
| Cluster | SQL node | \[ \] | \[ \] | \[ \] |

### SPNs

| SPN | Registered on | Used for | Created by |
| --- | --- | --- | --- |
| MSSQLSvc/\[host\]:\[port\] | \[SQL service account\] | SQL connections | \[ \] |
| MSSQLSvc/\[listener\]:\[port\] | \[ \] | Listener connections | \[ \] |
| HTTP/\[ssrs-name\] | \[SSRS account\] | SSRS portal | \[ \] |
| cifs/\[fsx-alias\] and HOST/\[fsx-alias\] | \[FSx computer account\] | UNC share access | \[FSx alias script\] |

### Delegation

| From | To | Type | Reason |
| --- | --- | --- | --- |
| \[SSRS\] | \[SQL, file share\] | \[Constrained\] | \[Pass user identity\] |

## 11. Certificates and TLS

| Certificate | Subject and SANs | Issuer | Installed on | Expiry | Renewal method | Used by |
| --- | --- | --- | --- | --- | --- | --- |
| SQL Server TLS | \[ \] | \[ \] | \[ \] | \[ \] | \[ \] | \[Force encryption\] |
| SSRS HTTPS | \[ \] | \[ \] | \[ \] | \[ \] | \[ \] | \[ \] |
| Load balancer | \[ \] | \[ACM\] | \[ \] | \[ \] | \[ \] | \[ \] |
| Availability group endpoint | \[ \] | \[ \] | \[ \] | \[ \] | \[ \] | \[ \] |
| Root and intermediate CA | \[ \] | \[ \] | \[All hosts\] | \[ \] | \[ \] | \[Trust chain\] |

## 12. DNS and aliases

| Name | Type | Points to | Zone | Purpose | Kerberos SPN needed |
| --- | --- | --- | --- | --- | --- |
| \[cluster name\] | A | \[ \] | \[ \] | WSFC | \[ \] |
| \[listener name\] | A | \[ \] | \[ \] | AG listener | \[ \] |
| \[fsx alias\] | CNAME | \[FSx DNS name\] | \[ \] | UNC share | \[ \] |
| \[ssrs name\] | CNAME or alias | \[Load balancer\] | \[ \] | SSRS portal | \[ \] |
| \[rds alias\] | CNAME | \[RDS endpoint\] | \[ \] | Database | \[ \] |

## 13. Windows configuration

| Area | Setting | Value | Applied by |
| --- | --- | --- | --- |
| Time | Time zone and NTP source | \[ \] | \[ \] |
| Features | Roles and features installed | \[Failover Clustering, .NET\] | \[ \] |
| Registry | TLS protocol and cipher settings | \[ \] | \[ \] |
| Registry | SSRS, SSIS and other keys | \[ \] | \[ \] |
| Security | Host firewall rules | \[ \] | \[ \] |
| Security | Antivirus exclusions | \[Data, log, backup paths\] | \[ \] |
| Performance | Power plan, page file | \[ \] | \[ \] |
| Patching | Method and window | \[SSM Patch Manager\] | \[ \] |
| Access | Admin groups, remote access | \[ \] | \[ \] |

## 14. Host rebuild and scaling

**Diagram 7: Rebuild and scale-out flow.** Shows the image pipeline, launch template, scheduled action, new instance boot, bootstrap steps, registration, health checks and scale-in lifecycle hook.

&#91;embedded content: rebuild and scale flow · 9 steps\]

The image pipeline builds the AMI, the scheduled action makes the scaling group launch from it, each new host bootstraps itself, and scale-in waits on the lifecycle hook so running packages finish first.

| Item | Value |
| --- | --- |
| Image build method | \[EC2 Image Builder or Packer\] |
| Baked in the image | \[SSIS, SSRS binaries, drivers, scripts\] |
| Configured at boot | \[Secrets, domain join, SSRS key restore, DB connection\] |
| Schedule | \[Daily at \_\_\_\] |
| Min, desired and max capacity | \[ \] |
| Health check and grace period | \[ \] |
| Scale-in protection and lifecycle hook | \[Wait for running packages\] |
| Failure handling | \[Retry limits, alerting\] |
| Infrastructure as code tool and repository | \[ \] |

## 15. Local test pipeline (AWS Emulator)

**Diagram 8: Emulator test flow.** Shows the test script, the emulator endpoint, the patched EC2 service, the Windows container acting as the instance, and the installer media in emulated S3.

&#91;embedded content: emulator test flow · 5 components\]

The script calls RunInstances on the emulator, whose patched EC2 service starts a Windows container through Docker; the container pulls installer media from emulated S3 and runs the real SSIS and SSRS setup.

| Item | Value |
| --- | --- |
| Emulator fork and pinned version | \[ \] |
| Windows host and Docker mode | \[ \] |
| AMI to image mapping | \[ \] |
| Mocked at API level | \[Clustering, FSx, domain join, Kerberos\] |
| Real in the container | \[SSIS and SSRS installation and services\] |
| Pass criteria | \[Services running, dtexec smoke test, SSRS responds\] |

## 16. Security, backup and operations

| Area | Decision |
| --- | --- |
| IAM roles and instance profiles | \[ \] |
| Secrets storage | \[Secrets Manager paths\] |
| Encryption at rest and in transit | \[KMS keys, TDE, forced TLS\] |
| Database backups and retention | \[ \] |
| Volume snapshots and AWS Backup plan | \[ \] |
| Disaster recovery region, RPO and RTO | \[ \] |
| Monitoring and alerts | \[CloudWatch agent, counters, alarms\] |
| Log destinations | \[SQL error log, event log, install logs, SSIS logs\] |
| Tagging standard | \[ \] |
| Licensing model | \[License included or BYOL, edition, core counts\] |

## 17. Risks, assumptions and open items

| # | Item | Type | Owner | Status |
| --- | --- | --- | --- | --- |
| 1 | \[ \] | \[Risk, assumption or question\] | \[ \] | \[ \] |

## 18. Change log

| Version | Date | Author | Change |
| --- | --- | --- | --- |
| 0.1 | 17 November 2026 | \[ \] | Initial template |
