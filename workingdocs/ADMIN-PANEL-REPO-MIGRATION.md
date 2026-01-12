# Admin Panel Repository Migration Plan

**Date:** January 2026  
**Status:** Planning Phase  
**Current State:** OpenSIPS repository exists; Laravel admin panel not yet created

## Executive Summary

This document outlines the plan for creating and maintaining a separate Laravel admin panel repository. The decision to separate repositories aligns with:
- Laravel Herd development workflow
- Docker containerization strategy
- Future AWS RDS cloud database deployment
- Clean separation of infrastructure vs application code

## Current State

### OpenSIPS Repository (`pbx3sbc`)
- **Location:** Current repository
- **Contents:**
  - OpenSIPS configuration (`config/opensips.cfg.template`)
  - Database initialization scripts (`scripts/init-database.sh`)
  - Helper scripts (`scripts/add-domain.sh`, `scripts/add-dispatcher.sh`, etc.)
  - Installation scripts (`install.sh`)
  - Documentation (`docs/`, `workingdocs/`)
- **Database Schema:**
  - Managed by `scripts/init-database.sh`
  - Uses OpenSIPS standard schema files from `/usr/share/opensips/mysql`
  - Custom modifications:
    - `domain.setid` column (added via init script)
    - `endpoint_locations` table (custom table)
- **Technology Stack:**
  - Bash scripts
  - MySQL database
  - OpenSIPS configuration

### Laravel Admin Panel Repository
- **Status:** Not yet created
- **Planned Name:** `pbx3sbc-admin` (or `opensips-admin`)
- **Technology Stack:** Laravel 10+ (PHP 8.2+)

## Target State

### Repository Structure

```
pbx3sbc/                          # OpenSIPS Infrastructure Repo
├── config/
├── scripts/
├── docs/
└── ...

pbx3sbc-admin/                    # Laravel Admin Panel Repo (NEW)
├── app/
├── database/
│   └── migrations/              # Laravel migrations for admin tables
├── routes/
├── config/
├── docker-compose.yml           # Local development with MySQL container
└── ...
```

### Database Schema Ownership

**Decision:** Laravel repository will own all database migrations, including OpenSIPS tables.

**Rationale:**
- Laravel migrations provide version control and rollback capabilities
- Single source of truth for database schema
- Easier to coordinate schema changes between OpenSIPS config and admin panel
- Supports future AWS RDS deployment (migrations can run independently)

**Migration Strategy:**
1. Laravel migrations will include:
   - OpenSIPS standard tables (domain, dispatcher, version)
   - Custom OpenSIPS modifications (domain.setid column, endpoint_locations table)
   - Admin panel tables (users, roles, user_roles, opensips_instances)
2. OpenSIPS repo `scripts/init-database.sh` will be updated to:
   - Option 1: Reference Laravel migrations (if Laravel available)
   - Option 2: Keep as fallback for standalone OpenSIPS installations
   - Option 3: Deprecate in favor of Laravel migrations (recommended)

**Recommended Approach:** Option 3 - Deprecate init-database.sh in favor of Laravel migrations.

## Migration Steps

### Phase 1: Repository Setup (Current - No Migration Needed)

Since the admin panel doesn't exist yet, no code migration is required. This phase involves:

1. ✅ **Decision:** Keep repositories separate (DONE)
2. ⏳ **Create Laravel repository:**
   - Initialize new Laravel project
   - Set up git repository
   - Configure initial project structure
3. ⏳ **Set up development environment:**
   - Configure Laravel Herd
   - Set up Docker Compose for local MySQL (optional)
   - Configure database connection

### Phase 2: Database Migration Strategy

**2.1 Laravel Migration Files**

Create Laravel migrations for all database tables:

```php
// database/migrations/YYYY_MM_DD_create_opensips_tables.php
// - domain table (with setid column)
// - dispatcher table
// - version table
// - endpoint_locations table

// database/migrations/YYYY_MM_DD_create_admin_tables.php
// - users table
// - roles table
// - user_roles table
// - opensips_instances table (future)
```

**2.2 Migration from init-database.sh**

- Extract SQL logic from `scripts/init-database.sh`
- Convert to Laravel migrations
- Document the migration in Laravel repo
- Update OpenSIPS repo documentation to reference Laravel migrations

**2.3 OpenSIPS Repository Changes**

- Update `scripts/init-database.sh` to:
  - Add comment noting Laravel migrations are preferred
  - Optionally: Check if Laravel migrations exist and suggest using them
- Update documentation to reference Laravel admin panel for database setup
- Keep script as fallback for standalone installations (if needed)

### Phase 3: Development Setup

**3.1 Laravel Herd Setup**
- Configure Laravel application for Herd
- Set up local domain (e.g., `pbx3sbc-admin.test`)
- Configure environment variables (`.env`)

**3.2 Database Configuration**

For local development:
- Option A: Use Docker Compose MySQL container
- Option B: Connect to local MySQL instance
- Option C: Connect to AWS RDS (for testing)

For production:
- Connect to AWS RDS MySQL/Aurora

**3.3 Docker Setup (Optional but Recommended)**

Create `docker-compose.yml` for local development:
```yaml
services:
  mysql:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: root
      MYSQL_DATABASE: opensips
      MYSQL_USER: opensips
      MYSQL_PASSWORD: password
    ports:
      - "3306:3306"
    volumes:
      - mysql_data:/var/lib/mysql

volumes:
  mysql_data:
```

### Phase 4: API Development

**4.1 Core Modules (MVP)**
- Authentication module
- Domain management API
- Dispatcher management API
- OpenSIPS MI integration

**4.2 Database Schema Updates**

Any schema changes (e.g., adding columns, new tables) will be:
- Created as Laravel migrations
- Documented in migration files
- Applied via `php artisan migrate`
- OpenSIPS repo scripts will assume schema exists

## Deployment Considerations

### Development Environment

**Laravel Admin Panel:**
- Runs on Laravel Herd (local)
- Connects to local MySQL or Docker MySQL container
- OpenSIPS MI endpoint: `http://localhost:8888/mi` (or remote)

**OpenSIPS:**
- Runs on server (localhost or remote)
- Connects to same MySQL database as admin panel
- Managed independently

### Production Environment (Future)

**AWS RDS MySQL:**
- Single RDS instance for both OpenSIPS and admin panel
- Admin panel connects via Laravel database configuration
- OpenSIPS connects via standard MySQL configuration
- Migrations run via Laravel deployment process

**Application Deployment:**
- Laravel admin panel: Deploy to EC2/ECS/Lambda (TBD)
- OpenSIPS: Deploy to EC2/ECS (TBD)
- Both connect to shared RDS database

## Database Schema Coordination

### Current Schema (OpenSIPS Repo)

Managed by `scripts/init-database.sh`:
- Standard OpenSIPS tables (domain, dispatcher, version)
- Custom `domain.setid` column
- Custom `endpoint_locations` table

### Future Schema (Laravel Repo)

Will be managed by Laravel migrations:
- All OpenSIPS tables (migrated from init-database.sh)
- All admin panel tables
- Single source of truth for schema

### Coordination Strategy

1. **Initial Setup:**
   - Laravel migrations include all tables
   - OpenSIPS repo scripts assume schema exists
   - OpenSIPS installation process can optionally run Laravel migrations (if available)

2. **Ongoing Development:**
   - Schema changes via Laravel migrations only
   - OpenSIPS repo scripts remain compatible with schema
   - Documentation updated in both repos if schema changes affect scripts

3. **Version Control:**
   - Schema version tracked by Laravel migrations
   - OpenSIPS scripts check for required columns/tables (defensive programming)
   - Migration files serve as documentation

## Testing Strategy

### Database Setup Testing

1. **Fresh Installation:**
   - Run Laravel migrations
   - Verify all tables exist
   - Test OpenSIPS scripts with new schema

2. **Migration Testing:**
   - Test migrations on fresh database
   - Test migrations on existing database (with data)
   - Verify backward compatibility

3. **Integration Testing:**
   - Test admin panel API with OpenSIPS database
   - Test OpenSIPS scripts with Laravel-managed schema
   - Verify data consistency

## Documentation Updates

### OpenSIPS Repository

Update documentation to reference Laravel admin panel:
- Installation guide: Mention Laravel migrations for database setup
- Database setup: Link to Laravel admin panel documentation
- Scripts documentation: Note schema is managed by Laravel migrations

### Laravel Repository

Create documentation:
- README with setup instructions
- Database migration documentation
- API documentation
- Development environment setup (Herd, Docker)
- Deployment guide (AWS RDS)

## Risks and Mitigations

### Risk 1: Schema Drift

**Risk:** OpenSIPS scripts and Laravel migrations get out of sync.

**Mitigation:**
- Single source of truth (Laravel migrations)
- OpenSIPS scripts use defensive checks (verify columns exist)
- Integration tests verify compatibility
- Documentation clearly states schema ownership

### Risk 2: Deployment Complexity

**Risk:** Two repositories require coordinated deployments.

**Mitigation:**
- Database schema changes via Laravel migrations (controlled)
- OpenSIPS scripts remain compatible with schema
- Clear documentation of dependencies
- Version tagging/releases for coordination

### Risk 3: Development Environment Setup

**Risk:** Developers need both repositories and correct database setup.

**Mitigation:**
- Clear documentation in both repos
- Docker Compose for local development (optional but helpful)
- Laravel migrations make database setup repeatable
- Helper scripts/documentation for first-time setup

## Timeline and Next Steps

### Immediate (Current Session)

1. ✅ Draft migration plan (this document)
2. ⏳ Review and approve migration plan
3. ⏳ Create Laravel repository structure

### Short Term (Next Sessions)

1. Set up Laravel project
2. Create initial migrations (OpenSIPS tables + admin tables)
3. Set up Laravel Herd development environment
4. Create Docker Compose setup (optional)
5. Begin API development (authentication, domain management)

### Medium Term

1. Complete MVP features
2. Test with existing OpenSIPS installation
3. Update OpenSIPS repository documentation
4. Prepare for AWS RDS deployment

## Success Criteria

- ✅ Laravel repository created and set up
- ✅ Database migrations created for all tables
- ✅ Development environment working (Laravel Herd)
- ✅ OpenSIPS scripts work with Laravel-managed schema
- ✅ Documentation updated in both repositories
- ✅ Clear separation of concerns maintained
- ✅ Ready for AWS RDS deployment

## Notes

- Since no admin panel code exists yet, this migration is primarily a planning document
- The actual "migration" is minimal - mostly about establishing the new repository structure
- Database schema migration is the main coordination point between repositories
- Future schema changes will be managed via Laravel migrations

---

**Document Owner:** Development Team  
**Last Updated:** January 2026  
**Status:** Draft - Awaiting Review
