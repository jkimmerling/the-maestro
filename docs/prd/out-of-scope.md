# 9. Out of Scope

**Goal:** Clearly define what features and capabilities are explicitly NOT included in this version.

## **Explicitly Excluded Features**

### **Multi-User & Collaboration**

- **Team Features:** No user management, permissions, or role-based access control
    
- **Session Sharing:** No ability to share sessions or conversations with other users
    
- **Collaborative Editing:** No real-time collaboration on documents or code
    
- **User Authentication:** No login system - single-user application assumed to run on trusted machine
    

### **Advanced Analytics & Reporting**

- **Usage Analytics:** No detailed usage patterns, productivity metrics, or performance analytics dashboard
    
- **Cost Optimization:** No automatic provider switching based on cost or performance
    
- **Conversation Analytics:** No sentiment analysis, topic modeling, or conversation insights
    
- **Export/Reporting:** No PDF reports, conversation exports, or business intelligence features
    

### **Enterprise Features**

- **Audit Logging:** No compliance-grade audit trails or security logging
    
- **High Availability:** No clustering, load balancing, or failover mechanisms
    
- **Backup/Recovery:** No automated backup systems or disaster recovery procedures
    
- **Enterprise Integration:** No LDAP, SAML, or enterprise SSO integration
    

## **Technical Limitations**

### **Scalability Constraints**

- **Concurrent Users:** Designed for single user only
    
- **Session Limits:** Practical limit of ~50 concurrent sessions (not tested beyond this)
    
- **Data Retention:** No automated archiving or data lifecycle management
    

### **Security Constraints**

- **Network Security:** No VPN integration, IP whitelisting, or network-level security
    
- **Encryption:** Basic credential encryption only, no end-to-end message encryption
    
- **Compliance:** No SOC2, HIPAA, or other compliance framework support
    

### **Integration Limitations**

- **Version Control:** No direct Git integration or version control features
    
- **IDE Integration:** No VS Code extensions, IntelliJ plugins, or similar IDE integrations
    
- **Cloud Storage:** No integration with cloud storage providers (AWS S3, Google Drive, etc.)
    

## **Future Considerations**

### **Potential V2 Features**

- Multi-user support with authentication system
    
- Advanced conversation search and organization
    
- Plugin system for custom tools beyond MCP
    
- Mobile companion app for session monitoring
    

### **Integration Roadmap**

- VS Code extension for inline agent interaction
    
- Git hooks for automatic code review using agents
    
- CI/CD pipeline integration for automated testing with agents
    

## **Boundary Clarifications**

- **File System Access:** Unlimited within user's permissions, but no privilege escalation
    
- **Code Execution:** Supports common languages but no custom runtime environments
    
- **Provider Support:** Limited to Anthropic, OpenAI, and Google Gemini initially
    
- **MCP Protocol:** Implements current MCP specification, may not support future protocol versions without updates

