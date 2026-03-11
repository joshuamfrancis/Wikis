# AWS EC2 Userdata — RHEL SSM Agent Setup

## Userdata Script

Paste the following into the **User data** field when launching an EC2 instance (or pass it via `--user-data` in the CLI):

```bash
#!/bin/bash
yum install -y https://s3.amazonaws.com/ec2-downloads-ssm-agent/latest/linux_amd64/amazon-ssm-agent.rpm
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent
```

## Prerequisites

### IAM Instance Profile

Attach an instance profile with the **AmazonSSMManagedInstanceCore** managed policy. Without this the agent will run but cannot register with Systems Manager.

Example trust policy for the role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

### Network Access

The instance needs outbound HTTPS (port 443) to the following endpoints (replace `<region>` with your AWS region):

| Endpoint | Purpose |
|---|---|
| `ssm.<region>.amazonaws.com` | Systems Manager service |
| `ssmmessages.<region>.amazonaws.com` | Session Manager messaging |
| `ec2messages.<region>.amazonaws.com` | EC2 message delivery |

For instances in a **private subnet** with no internet gateway, create VPC interface endpoints for these three services instead.

## Verification

After the instance launches, connect via Session Manager or SSH and run:

```bash
systemctl status amazon-ssm-agent
```

You should see `active (running)`. You can also confirm registration in the AWS console under **Systems Manager → Fleet Manager**.

## Notes

- Recent Amazon-provided RHEL AMIs may already include the SSM agent. The userdata script is idempotent — it will update or confirm the existing installation.
- For RHEL 9+ with `dnf` as the default package manager, `yum` is still available as a compatibility symlink, so the script works on both RHEL 8 and 9.
