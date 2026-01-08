# OpenSIPS Admin Panel - Design Document

**Date:** January 2026  
**Version:** 1.0  
**Status:** Design Phase

## Executive Summary

This document outlines the design for a modern replacement of the OpenSIPS Control Panel (OCP). The goal is to create a clean, maintainable, extensible web application that can grow with requirements while avoiding technical debt from patching upstream code.

## Design Principles

1. **Separation of Concerns** - Clean API/UI separation
2. **Extensibility** - Easy to add new features/modules over time
3. **Multi-Instance Ready** - Architecture supports managing multiple OpenSIPS servers
4. **Modern UX** - Intuitive, responsive interface
5. **No Core Modifications** - OpenSIPS core remains untouched
6. **Maintainability** - Clean code, good documentation, testable

## Architecture Overview

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Frontend (SPA)                          │
│  React/Vue/Angular - Modern UI Framework                    │
│  - Domain Management                                         │
│  - Dispatcher Management                                     │
│  - Statistics/Dashboards (future)                           │
│  - Authentication/Authorization                             │
└───────────────────────┬─────────────────────────────────────┘
                        │ HTTPS/REST API
┌───────────────────────┴─────────────────────────────────────┐
│                    Backend API Service                       │
│  Language: Node.js / PHP 8+ / Python                        │
│  Framework: Express / Laravel / FastAPI                      │
│  - REST API endpoints                                        │
│  - Business logic                                            │
│  - Authentication/Authorization                              │
│  - Multi-instance routing (future)                           │
└───────────────┬──────────────────────┬──────────────────────┘
                │                      │
        ┌───────┴──────┐      ┌───────┴──────┐
        │   MySQL DB   │      │  OpenSIPS MI │
        │   (local)    │      │  (HTTP/JSON) │
        └──────────────┘      └──────────────┘
```

### Deployment Evolution

**Phase 1: Colocated (Initial)**
- Frontend and API on same server
- Direct database access
- Single OpenSIPS instance

**Phase 2: Multi-Instance (Future)**
- API can be moved to separate service
- API routes requests to multiple OpenSIPS instances
- Instance configuration management
- Load balancing/failover for API

## Technical Stack Recommendations

### Option A: Node.js Stack (Recommended)

**Backend:**
- **Runtime:** Node.js 18+ LTS
- **Framework:** Express.js or Fastify
- **Database:** MySQL2 or Prisma ORM
- **Authentication:** JWT + bcrypt
- **Validation:** Joi or Zod

**Frontend:**
- **Framework:** React 18+ with TypeScript
- **State Management:** React Query / TanStack Query
- **UI Library:** Tailwind CSS + shadcn/ui or Material-UI
- **HTTP Client:** Axios or Fetch API
- **Build Tool:** Vite

**Why Node.js:**
- Single language (JavaScript/TypeScript) for full stack
- Excellent async/await support for API calls
- Large ecosystem
- Good performance
- Easy deployment

### Option B: PHP Stack (If Prefer Existing Skills)

**Backend:**
- **Runtime:** PHP 8.2+
- **Framework:** Laravel 10+ or Symfony
- **Database:** Eloquent ORM or Doctrine
- **Authentication:** Laravel Sanctum / Passport

**Frontend:**
- **Framework:** React/Vue (separate from backend)
- Same frontend stack as Option A

**Why PHP:**
- Team familiarity (if applicable)
- Existing PHP infrastructure
- Laravel provides robust API framework
- Good for rapid development

### Option C: Python Stack

**Backend:**
- **Runtime:** Python 3.11+
- **Framework:** FastAPI
- **Database:** SQLAlchemy
- **Authentication:** JWT

**Frontend:**
- Same as Option A

**Why Python:**
- Excellent for data processing (future CDR/statistics)
- FastAPI is modern and fast
- Good for analytics features

**Recommendation:** Node.js (Option A) for consistency and modern tooling

## Core Modules (MVP)

### 1. Authentication & Authorization

**Features:**
- User login/logout
- Session management (JWT)
- Role-based access control (RBAC)
- Password management

**API Endpoints:**
```
POST   /api/auth/login
POST   /api/auth/logout
POST   /api/auth/refresh
GET    /api/auth/me
PUT    /api/auth/password
```

**Database:**
- `users` table (separate from OpenSIPS data)
- `roles` table
- `permissions` table

### 2. Domain Management

**Features:**
- List domains
- Add domain
- Edit domain
- Delete domain
- Domain validation
- Link to dispatcher set ID (explicit or via domain.id)

**API Endpoints:**
```
GET    /api/domains
GET    /api/domains/:id
POST   /api/domains
PUT    /api/domains/:id
DELETE /api/domains/:id
POST   /api/domains/:id/reload  (MI command)
```

**Database:**
- `domain` table (OpenSIPS standard table, with added `setid` column)
- **Decision:** Add `setid` column to domain table (explicit mapping)
- **Rationale:** IDs are surrogate keys and should be allowed to change. Explicit setid provides flexibility and decouples domain identity from dispatcher routing.

**Schema Modification:**
```sql
ALTER TABLE domain ADD COLUMN setid INT NOT NULL DEFAULT 0;
-- Migration: Set setid to id for existing domains (one-time)
UPDATE domain SET setid = id WHERE setid = 0;
-- Add index for setid lookups
CREATE INDEX idx_domain_setid ON domain(setid);
```

**Data Model:**
```typescript
interface Domain {
  id: number;              // Surrogate key (can change)
  domain: string;
  setid: number;           // Explicit dispatcher set ID (stable routing identifier)
  attrs?: string;
  accept_subdomain: number;
  last_modified: string;
}
```

### 3. Dispatcher Management

**Features:**
- List dispatcher destinations
- Add destination (with set ID)
- Edit destination
- Delete destination
- Set state (active/inactive)
- View health status
- Group by set ID
- Filter by set ID

**API Endpoints:**
```
GET    /api/dispatcher
GET    /api/dispatcher/sets/:setid
GET    /api/dispatcher/:id
POST   /api/dispatcher
PUT    /api/dispatcher/:id
DELETE /api/dispatcher/:id
POST   /api/dispatcher/:id/set-state
POST   /api/dispatcher/reload  (MI command)
GET    /api/dispatcher/stats   (health/status)
```

**Database:**
- `dispatcher` table (OpenSIPS standard table)

**Data Model:**
```typescript
interface DispatcherDestination {
  id: number;
  setid: number;
  destination: string;
  socket?: string;
  state: number;  // 0=active, 1=inactive, etc.
  weight: string;
  priority: number;
  attrs?: string;
  description?: string;
  probe_mode: number;
}
```

### 4. Multi-Instance Management (Future)

**Features:**
- Add/remove OpenSIPS instances
- Instance configuration (MI endpoint, database connection)
- Instance health monitoring
- Route API requests to specific instances

**API Endpoints:**
```
GET    /api/instances
GET    /api/instances/:id
POST   /api/instances
PUT    /api/instances/:id
DELETE /api/instances/:id
GET    /api/instances/:id/health
```

**Database:**
- `instances` table (new)
- Links domains/dispatcher operations to specific instances

## Database Design

### Core Tables (OpenSIPS - Existing, with Modifications)

- `domain` - SIP domains (with added `setid` column for explicit dispatcher mapping)
- `dispatcher` - Dispatcher destinations
- `version` - Schema version tracking

**Domain Table Modification:**
```sql
-- Add setid column to domain table
ALTER TABLE domain ADD COLUMN setid INT NOT NULL DEFAULT 0;

-- Migration: Set setid to id for existing domains (one-time)
UPDATE domain SET setid = id WHERE setid = 0;

-- Add index for setid lookups (performance)
CREATE INDEX idx_domain_setid ON domain(setid);
```

**Note:** While this modifies the OpenSIPS schema, it's an additive change that doesn't break existing functionality. The domain module doesn't use the setid column - it's purely for our routing logic.

### Application Tables (New)

```sql
-- Users and authentication
CREATE TABLE users (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  username VARCHAR(64) UNIQUE NOT NULL,
  email VARCHAR(255),
  password_hash VARCHAR(255) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Roles (optional, for RBAC)
CREATE TABLE roles (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(64) UNIQUE NOT NULL,
  description TEXT
);

-- User roles (many-to-many)
CREATE TABLE user_roles (
  user_id INT UNSIGNED,
  role_id INT UNSIGNED,
  PRIMARY KEY (user_id, role_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE
);

-- OpenSIPS Instances (future multi-instance support)
CREATE TABLE opensips_instances (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(128) NOT NULL,
  description TEXT,
  mi_url VARCHAR(255) NOT NULL,  -- e.g., "http://192.168.1.58:8888/mi"
  db_host VARCHAR(255),
  db_port INT,
  db_name VARCHAR(64),
  db_user VARCHAR(64),
  db_password VARCHAR(255),  -- Encrypted
  enabled BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);
```

### Extensibility Considerations

**Future Tables (as needed):**
- `cdr` / `acc` - Call Detail Records (OpenSIPS accounting)
- `trunks` - SIP trunk configuration
- `ddi` - Direct Dial-In numbers
- `statistics` - Aggregated statistics
- `alarms` / `events` - Monitoring and alerts

**Design Pattern:**
- Each new feature gets its own table(s)
- API endpoints follow RESTful conventions
- Frontend modules are loosely coupled

## API Design

### RESTful Conventions

- **GET** - Retrieve resources
- **POST** - Create resources
- **PUT** - Update resources (full update)
- **PATCH** - Partial updates
- **DELETE** - Delete resources

### Response Format

```typescript
// Success response
{
  "success": true,
  "data": { ... },
  "meta": { ... }  // Optional: pagination, etc.
}

// Error response
{
  "success": false,
  "error": {
    "code": "DOMAIN_NOT_FOUND",
    "message": "Domain not found",
    "details": { ... }
  }
}
```

### Authentication

- JWT tokens in Authorization header
- Token expiration and refresh
- Secure cookie storage (for browser)

### OpenSIPS MI Integration

**Abstraction Layer:**
```typescript
class OpenSIPSMIClient {
  async call(method: string, params?: any): Promise<any>
  async domainReload(): Promise<void>
  async dispatcherReload(): Promise<void>
  async dispatcherSetState(setid: number, destination: string, state: number): Promise<void>
  // ... more methods
}
```

**Implementation:**
- HTTP POST to OpenSIPS MI endpoint
- JSON-RPC format
- Error handling and retries
- Support for multiple instances (future)

## Frontend Design

### Component Structure

```
src/
├── components/
│   ├── common/           # Reusable UI components
│   ├── domains/          # Domain management components
│   ├── dispatcher/       # Dispatcher management components
│   └── layout/           # Layout components (header, sidebar, etc.)
├── pages/
│   ├── Login.tsx
│   ├── Dashboard.tsx
│   ├── Domains.tsx
│   └── Dispatcher.tsx
├── services/
│   ├── api.ts            # API client
│   ├── auth.ts           # Authentication service
│   └── opensips-mi.ts    # MI client abstraction
├── hooks/                # Custom React hooks
├── utils/                # Utility functions
└── types/                # TypeScript types
```

### UI/UX Considerations

- **Responsive Design** - Works on desktop, tablet, mobile
- **Dark Mode** - Optional theme toggle
- **Real-time Updates** - WebSocket or polling for stats
- **Form Validation** - Client-side validation with clear errors
- **Loading States** - Spinners, skeletons
- **Error Handling** - User-friendly error messages
- **Confirmation Dialogs** - For destructive actions

## Security Considerations

1. **Authentication**
   - Secure password hashing (bcrypt/Argon2)
   - JWT with appropriate expiration
   - HTTPS only in production

2. **Authorization**
   - Role-based access control
   - API endpoint protection
   - Database query sanitization (prepared statements)

3. **Input Validation**
   - Client-side and server-side validation
   - SQL injection prevention (ORM/prepared statements)
   - XSS prevention (sanitize output)

4. **API Security**
   - Rate limiting
   - CORS configuration
   - Request size limits

5. **Database**
   - Encrypted connections
   - Credential management (environment variables)
   - Backup and recovery procedures

## Deployment Architecture

### Phase 1: Colocated (Single Server)

```
Server: 192.168.1.58
├── OpenSIPS (port 5060)
├── MySQL (port 3306)
├── Admin Panel API (port 3000/internal)
└── Admin Panel Frontend (port 80/443, served by API or nginx)
```

### Phase 2: Multi-Instance (Future)

```
Admin Panel Server
├── Frontend (port 80/443)
└── API Service (port 3000)
    ├── Instance Manager
    └── Routing Layer
        ├── OpenSIPS Instance 1 (192.168.1.58)
        ├── OpenSIPS Instance 2 (192.168.1.59)
        └── OpenSIPS Instance N
```

## Development Roadmap

### Phase 1: MVP (Weeks 1-4)
- [ ] Project setup and scaffolding
- [ ] Authentication module
- [ ] Domain management (CRUD)
- [ ] Dispatcher management (CRUD)
- [ ] Basic UI/UX
- [ ] OpenSIPS MI integration
- [ ] Testing and documentation

### Phase 2: Enhancement (Weeks 5-8)
- [ ] Advanced features (search, filters, pagination)
- [ ] Statistics/dashboards
- [ ] Health monitoring
- [ ] Better error handling
- [ ] Performance optimization

### Phase 3: Future Features
- [ ] CDR/Accounting module
- [ ] Trunking management
- [ ] DDI management
- [ ] Multi-instance support
- [ ] Advanced analytics
- [ ] Alerting/notifications

## Migration Strategy

### From Current Control Panel

1. **Data Migration**
   - Export domains from current panel
   - Export dispatcher entries
   - Import into new system
   - Verify data integrity

2. **User Migration**
   - Create user accounts in new system
   - Set up authentication
   - Configure permissions

3. **Deployment**
   - Run new panel on different port initially
   - Test thoroughly
   - Switch over when ready
   - Keep old panel as backup for short period

4. **Cleanup**
   - Remove old control panel
   - Clean up unused tables/config

## Technology Choices Summary

**Recommended Stack:**
- **Backend:** Node.js + Express.js + TypeScript
- **Frontend:** React + TypeScript + Tailwind CSS
- **Database:** MySQL (existing)
- **Authentication:** JWT
- **Build Tool:** Vite (frontend)
- **Package Manager:** npm or pnpm

**Alternative Stacks:**
- PHP/Laravel + React (if team prefers PHP)
- Python/FastAPI + React (if analytics-heavy future)

## Design Decisions

1. **Domain → Set ID Mapping:**
   - **Decision:** Add `setid` column to domain table
   - **Rationale:** IDs are surrogate keys and should be allowed to change. Explicit setid column provides:
     - Decoupling of domain identity from routing
     - Flexibility to change set IDs independently
     - Better alignment with best practices (explicit over implicit)
     - Easier to understand and maintain
   - **Implementation:** Modify domain table schema to add `setid INT NOT NULL` column
   - **Migration:** Existing domains will need setid values assigned (can default to id initially)

2. **Database Access:**
   - Direct access from API (Phase 1)
   - Separate database service layer (Phase 2 multi-instance)
   - Consider connection pooling

3. **Real-time Updates:**
   - WebSocket for live stats?
   - Polling sufficient initially?
   - Server-Sent Events (SSE)?

4. **Deployment:**
   - Docker containers?
   - Systemd services?
   - Cloud deployment considerations?

## Success Criteria

- ✅ Modern, intuitive user interface
- ✅ All MVP features working
- ✅ No modifications to OpenSIPS core
- ✅ Clean, maintainable codebase
- ✅ Extensible architecture for future features
- ✅ Production-ready security
- ✅ Good documentation
- ✅ Performance meets requirements

## Next Steps

1. Review and approve design
2. Decide on tech stack
3. Set up development environment
4. Create project repository
5. Begin Phase 1 development
6. Regular reviews and iterations

---

**Document Owner:** Development Team  
**Last Updated:** January 2026  
**Status:** Draft - Awaiting Review

