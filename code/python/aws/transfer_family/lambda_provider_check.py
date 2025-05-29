import ipaddress
import json
import os


def lambda_handler(event, context):
    username = event.get("username", "")
    password = event.get("password", "")
    source_ip = event.get("sourceIp", "")
    protocol = event.get("protocol", "")

    print(
        f"Authentication attempt for user: {username} from IP: {source_ip} using protocol: {protocol}"
    )
    print(f"Full event: {json.dumps(event)}")

    allowed_ips = [
        "203.0.113.0/24",      # Replace with your allowed IP ranges
        "198.51.100.5",        # Single IP
        "192.0.2.0/24",        # Another IP range
        "10.0.0.0/8",          # Private network range
        # Add more IPs/ranges as needed
    ]

    if not is_ip_allowed(source_ip, allowed_ips):
        print(f"Access denied: IP {source_ip} is not whitelisted")
        return {}

    BUCKET_NAME = "your-bucket-name"  # Replace with your bucket name
    TRANSFER_ROLE_ARN = "arn:aws:iam::YOUR-ACCOUNT-ID:role/TransferFamilyUserRole"  # Replace with your role ARN

    valid_users = {
        "user1": {
            "password": "",
            "public_keys": os.environ.get("USER1_PUBLIC_KEYS", "").split(","),
        },
        "user2": {
            "password": "",
            "public_keys": os.environ.get("USER2_PUBLIC_KEYS", "").split(","),
        },
    }

    if username not in valid_users:
        print(f"User {username} not found")
        return {}

    user_config = valid_users[username]

    response_data = {}

    # if password:
    #     if password != user_config.get("password"):
    #         print(f"Invalid password for user {username}")
    #         return {}
    #     print(f"Password authentication successful for user: {username}")

    # Disable password authentication
    if password:
        print("Password authentication is disabled")
        return {}

    elif protocol == "SFTP":
        print(f"SFTP key-based authentication for user: {username}")
        public_keys = user_config.get("public_keys", [])
        if not public_keys:
            print(f"No public keys configured for user: {username}")
            return {}
        response_data["PublicKeys"] = public_keys
        print(f"Returning public keys for user {username}: {public_keys}")

    else:
        print("No valid authentication method provided")
        return {}

    response_data["Role"] = TRANSFER_ROLE_ARN
    response_data["HomeDirectoryType"] = "LOGICAL"

    directory_mapping = [{"Entry": "/", "Target": f"/{BUCKET_NAME}/{username}"}]
    response_data["HomeDirectoryDetails"] = json.dumps(directory_mapping)

    session_policy = {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "AllowListBucketInUserFolder",
                "Effect": "Allow",
                "Action": ["s3:ListBucket"],
                "Resource": f"arn:aws:s3:::{BUCKET_NAME}",
                "Condition": {"StringLike": {"s3:prefix": [f"{username}/*", username]}},
            },
            {
                "Sid": "AllowUserAccessToTheirFolder",
                "Effect": "Allow",
                "Action": [
                    "s3:PutObject",
                    "s3:PutObjectAcl",
                    "s3:GetObject",
                    "s3:GetObjectAcl",
                    "s3:GetObjectVersion",
                    "s3:DeleteObject",
                    "s3:DeleteObjectVersion",
                    "s3:GetBucketLocation",
                ],
                "Resource": [
                    f"arn:aws:s3:::{BUCKET_NAME}/{username}",
                    f"arn:aws:s3:::{BUCKET_NAME}/{username}/*",
                ],
            },
        ],
    }

    response_data["Policy"] = json.dumps(session_policy)

    print(f"Authentication successful for user: {username} from IP: {source_ip}")
    print(f"Returning response: {json.dumps(response_data)}")  # Debug: log response

    return response_data


def is_ip_allowed(source_ip, allowed_ips):
    """Check if the source IP is in the allowed list"""
    try:
        source = ipaddress.ip_address(source_ip)

        for allowed in allowed_ips:
            if "/" in allowed:
                network = ipaddress.ip_network(allowed, strict=False)
                if source in network:
                    return True
            else:
                if source == ipaddress.ip_address(allowed):
                    return True
        return False
    except ValueError as e:
        print(f"Invalid IP address: {source_ip}, error: {e}")
        return False
