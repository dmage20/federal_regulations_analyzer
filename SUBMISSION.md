# USDS Engineering Take-Home Assessment - Submission

## Project Overview

**Federal Regulation Analyzer** - A Rails 8.1 web application that downloads, stores, and analyzes federal regulation data from the eCFR (Electronic Code of Federal Regulations) to provide digestible insights for deregulation efforts.

**Live Demo**: https://ecfr-analyzer-61ai.onrender.com

---

## Duration

**6-8 hours** (excluding initial setup and deployment configuration)

---

## Key Features

### 1. Data Download & Storage
- **Bulk Download Optimization**: Downloads complete CFR title XML files from govinfo.gov bulk repository
- **Streaming XML Parser**: Uses Nokogiri::XML::Reader for memory-efficient processing
- **24-hour Caching**: Reduces redundant downloads with local file cache
- **PostgreSQL Storage**: Three-model architecture (Agency, Regulation, RegulationSnapshot)

### 2. Server-Side APIs
- **MCP (Model Context Protocol) HTTP Endpoint**: JSON-RPC 2.0 API at `/mcp`
  - `get_agency_stats` - Retrieve statistics for a specific agency by acronym
  - `list_agencies` - List agencies ranked by total regulatory word count
  - `search_regulations` - Search regulations by CFR title and part number
- **RESTful Routes**: Dashboard UI and manual sync triggers

### 3. Analytics & Metrics

**Required Metrics:**
- **Word Count per Agency**: Tracks total words across all regulations
- **Historical Changes**: RegulationSnapshot model tracks changes over time via checksum comparison
- **Checksum per Agency**: SHA256 hash for detecting content changes

**Custom Metric - Restrictions Count:**
- Counts binding constraint words: `shall`, `must`, `may not`, `prohibited`, `required`
- Provides actionable regulatory burden insights
- Calculated on-the-fly during XML parsing (no content storage required)
- Enables comparison of regulatory strictness across agencies

### 4. User Interface
- **Dashboard**: Real-time analytics with key metrics cards
- **Top Agencies Chart**: Visual representation of word counts (Chartkick)
- **Agency Details Table**: Sortable table with word counts, restrictions, checksums
- **Most Frequently Changed Regulations**: Historical change tracking
- **System Health Page**: Queue depth, API status, manual sync controls

---

## Technical Highlights

### Performance Optimization (Primary Focus)

**Problem**: Initial implementation crashed with Out of Memory (OOM) errors when processing EPA's Title 40 (152MB XML, 357 parts) on Render.com's 500MB RAM limit for free tier.

**Solution 1 - Streaming Metrics Calculation**:
- Replaced content accumulation with on-the-fly metric calculation
- Memory usage: 500MB+ → 150MB constant
- Process 150MB+ files with <200MB RAM footprint

**Solution 2 - Bulk Download Approach**:
- Discovered USGPO govinfo.gov bulk data repository
- Changed from 357+ individual API calls to 1 bulk file download per title
- Performance improvement: 65+ minutes → 6 minutes (95% faster) for the biggest titles.
- Eliminated rate limiting concerns

**Solution 3 - Memory Optimization**:
- Explicit `GC.start` between parts processing
- Streaming parser yields parts instead of accumulating
- No XML content stored in database (only calculated metrics)

**Results**:
- ✅ Successfully processes Title 40 (152.91 MB, 388 parts) in ~90 seconds
- ✅ Full EPA sync (5 titles, 2,162 parts) in 6-7 minutes
- ✅ Zero OOM crashes on 500MB RAM constraint
- ✅ Handles all 50 CFR titles without memory issues

### Full-Stack Completeness

**Backend**:
- Rails 8.1 with SolidQueue for background jobs
- SolidCache for Rails.cache
- PostgreSQL database with migrations
- Background job processing (SyncAgencyJob, SyncAllAgenciesJob)

**Frontend**:
- Tailwind CSS responsive design
- Chartkick for data visualization
- Server-side rendering (no JavaScript framework dependency)

**API Integration**:
- MCP server for AI agent queries
- HTTP proxy at `/mcp` endpoint
- Three tools for programmatic access

### Production Deployment

**Platform**: Render.com
- Successfully deployed with 500MB RAM constraint
- PostgreSQL database
- Recurring background jobs via config/recurring.yml
- Production-grade error tracking with Sentry
- Structured logging with Lograge

**Reliability**:
- Retry logic with exponential backoff
- Graceful error handling
- Job queue monitoring

---

## Code Quality

**Lines of Code**: ~975 Ruby lines (excluding tests, auto-generated files, and tooling)
- Well under the 1,200 line recommendation
- Focused, maintainable codebase

**Architecture**:
- Service objects (EcfrBulkClient, EcfrClient)
- Background jobs for async processing
- Model layer with calculated attributes
- Clean separation of concerns

---

## Testing Note

Unit tests and feature tests would be an important part of a production system, but due to time constraints I focused on production deployment as proof of functionality. The live deployment at https://ecfr-analyzer-61ai.onrender.com demonstrates the system working end-to-end with real federal regulation data.

---

## Screenshots

### 1. Main Dashboard
![Main Dashboard](screenshots/01-dashboard-main.png)

**Shows**:
- Key metrics cards (Total Agencies, Regulations, Words, Average)
- Top 15 Agencies by Word Count (bar chart)
- Agency Details Table with word counts, restrictions count, and checksums
- Most Frequently Changed Regulations section

### 2. System Health Page
![System Health](screenshots/02-system-health.png)

**Shows**:
- Current system status (API status, queue depth, last sync)
- Manual agency sync controls
- All agencies with last sync timestamps

---

## Feedback on Assignment

### What Worked Well

1. **Well-Scoped Problem**: The 4-hour target was realistic for a lightweight solution. The assignment encouraged focusing on working software over perfect code.

2. **Real-World Constraints**: Working with actual eCFR data revealed realistic challenges (OOM errors, rate limiting, large file sizes) that required creative solutions.

3. **Meaningful Metrics**: The requirement to add a custom metric encouraged thinking about what would actually help decision-makers. The "Restrictions Count" metric provides actionable regulatory burden insights.

4. **Technology Freedom**: The open-ended tech stack choice allowed me to leverage Rails 8's modern features (SolidQueue, SolidCache, Propshaft) without legacy baggage.

### How My Expertise Fits

**Strengths Demonstrated**:
- **Performance Optimization**: Identified and resolved memory bottlenecks through profiling and architectural changes
- **Pragmatic Problem-Solving**: Discovered govinfo.gov bulk data as a simpler, faster alternative to complex API orchestration
- **Full-Stack Development**: Delivered working UI, API, background jobs, and production deployment
- **Production Mindset**: Deployed to real infrastructure with monitoring, error tracking, and operational visibility

**Rails 8 Expertise**:
- Modern Rails patterns (service objects, background jobs, caching)
- Streaming data processing for memory efficiency
- Database optimization and indexing

**DevOps/Infrastructure**:
- Production deployment with resource constraints
- Docker awareness (Kamal config included but not used)
- Monitoring and observability setup

### Areas for Improvement (Given More Time)

1. **Test Coverage**: Unit tests for models, integration tests for jobs, system tests for UI
2. **Error Recovery**: More sophisticated retry strategies, dead letter queue for failed jobs
3. **Performance**: Database query optimization, connection pooling, CDN for static assets
4. **UX Enhancements**: Real-time progress updates, pagination, advanced filtering
5. **Documentation**: API documentation, deployment runbook, contributing guide

---

## How to Run Locally

```bash
# Clone and setup
git clone <repository>
cd ecfr-analyzer
bundle install
bin/rails db:create db:migrate

# Start development server
bin/dev

# Sync all agencies (background job)
bin/rails runner "SyncAllAgenciesJob.perform_now"

# Or sync specific agency
bin/rails runner "SyncAgencyJob.perform_now(agency_data: {...}, sync_log_id: ...)"
```

---

## Repository Structure

```
app/
├── controllers/      # Dashboard and MCP endpoints
├── jobs/            # Background sync jobs
├── models/          # Agency, Regulation, RegulationSnapshot
├── services/        # EcfrBulkClient, EcfrClient
└── views/           # Dashboard UI

bin/
└── mcp-server       # MCP JSON-RPC server for AI agents

config/
├── deploy.yml       # Kamal deployment (optional, not used)
└── recurring.yml    # Scheduled background jobs

db/migrate/          # Database migrations
```

---

## Dependencies

**Core**:
- Rails 8.1.1
- PostgreSQL
- Nokogiri (XML parsing)
- SolidQueue (background jobs)
- SolidCache (caching)

**UI**:
- Tailwind CSS
- Chartkick (charts)

**Observability**:
- Sentry (error tracking)
- Lograge (structured logging)

---

## Conclusion

This project demonstrates my ability to:
- Build production-ready full-stack applications under time constraints
- Optimize for performance and resource efficiency
- Make pragmatic architectural decisions
- Deploy and monitor real systems

The live deployment proves that the system works end-to-end with real federal regulation data, handling over 200,000 pages of regulations across 150+ agencies.

Thank you for the opportunity to work on this assessment. I look forward to discussing the technical decisions and trade-offs made during implementation.

---

**Submitted by**: Daniel Mage
**Submission Date**: January 3, 2026
**Live Demo**: https://ecfr-analyzer-61ai.onrender.com
