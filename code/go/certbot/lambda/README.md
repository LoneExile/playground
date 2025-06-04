# certbot with lambda

run container > s3 > certbot[container] > cname > alb:80 > target group > lambda > certbot[container]


## 1. Infrastructure & Flow Diagram

```mermaid
graph TB
    subgraph "Setup Phase"
        A[Certbot Container] -->|1. Register account| LE[Let's Encrypt]
        A -->|2. Extract JWK| JWK[Account JWK]
        A -->|3. Upload JWK| S3[S3 Bucket]
    end
    
    subgraph "AWS Infrastructure"
        S3 -->|JWK stored| S3
        ALB[Application Load Balancer :80]
        TG[Target Group]
        Lambda[Lambda Function]
        ALB --> TG
        TG --> Lambda
        Lambda -->|Fetch JWK| S3
    end
    
    subgraph "Domain & DNS"
        Domain[yourdomain.com]
        CNAME[CNAME Record]
        Domain --> CNAME
        CNAME -->|Points to| ALB
    end
    
    subgraph "Challenge Flow"
        A -->|4. Request certificate| LE
        LE -->|5. HTTP-01 Challenge| Validation[Challenge: .well-known/acme-challenge/token]
        LE -->|6. GET request| Domain
        Lambda -->|7. Serve response| LE
        LE -->|8. Issue certificate| A
        A -->|9. Upload cert| S3
    end
    
    style A fill:#e1f5fe
    style LE fill:#f3e5f5
    style Lambda fill:#fff3e0
    style S3 fill:#e8f5e8
    style ALB fill:#fce4ec
```

## 2. Sequence Diagram - Challenge Process

```mermaid
sequenceDiagram
    participant CB as Certbot Container
    participant LE as Let's Encrypt
    participant S3 as S3 Bucket
    participant DNS as DNS/CNAME
    participant ALB as Load Balancer
    participant LF as Lambda Function

    Note over CB,LF: Setup Phase
    CB->>LE: 1. Register account (email)
    LE-->>CB: Account created + private key
    CB->>CB: 2. Extract JWK from private key
    CB->>S3: 3. Upload JWK to S3
    
    Note over CB,LF: Certificate Request
    CB->>LE: 4. Request certificate for domain
    LE-->>CB: 5. Challenge: serve token at /.well-known/acme-challenge/{token}
    
    Note over CB,LF: Validation Phase
    LE->>DNS: 6. DNS lookup for domain
    DNS-->>LE: CNAME points to ALB
    LE->>ALB: 7. GET /.well-known/acme-challenge/{token}
    ALB->>LF: 8. Forward request to Lambda
    LF->>S3: 9. Fetch JWK
    S3-->>LF: JWK data
    LF->>LF: 10. Calculate thumbprint from JWK
    LF-->>ALB: 11. Return: {token}.{thumbprint}
    ALB-->>LE: 12. Forward response
    
    Note over CB,LF: Certificate Issuance
    LE->>LE: 13. Validate response
    LE-->>CB: 14. Challenge passed - issue certificate
    CB->>S3: 15. Upload certificate to S3
    
    Note over CB,LF: Container keeps running for renewals
```

## 3. Component Interaction Diagram

```mermaid
graph LR
    subgraph "Container Environment"
        CB[Certbot Container]
        AK[Account Key]
        JWK[JWK Extract]
    end
    
    subgraph "AWS Services"
        S3[(S3 Bucket)]
        ALB{ALB :80}
        Lambda["🔧 Lambda Function<br/>Challenge Responder"]
    end
    
    subgraph "External"
        LE[🔒 Let's Encrypt]
        Domain[🌐 Your Domain]
    end
    
    CB -.->|register| LE
    CB -->|extract| AK
    AK -->|format| JWK
    JWK -->|upload| S3
    CB -->|request cert| LE
    
    LE -->|validate| Domain
    Domain -->|CNAME| ALB
    ALB -->|route| Lambda
    Lambda <-->|fetch JWK| S3
    Lambda -->|token.thumbprint| ALB
    ALB -->|response| LE
    
    LE -.->|issue cert| CB
    CB -->|store cert| S3
    
    style CB fill:#bbdefb
    style LE fill:#f8bbd9
    style Lambda fill:#fff9c4
    style S3 fill:#c8e6c9
    style ALB fill:#ffcdd2
```

