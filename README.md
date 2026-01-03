# Federal Regulation Analyzer

A Rails 8.1 web application that downloads, stores, and analyzes federal regulation data from the eCFR (Electronic Code of Federal Regulations).

**Live Demo**: https://ecfr-analyzer-61ai.onrender.com

---

## 📄 Full Documentation

**For complete project details, technical architecture, and submission information, see [SUBMISSION.md](SUBMISSION.md)**

The SUBMISSION.md document includes:
- Project overview and key features
- Technical highlights and performance optimizations
- Screenshots and demo video
- Code quality metrics
- Feedback on the assignment

---

## Quick Start

### Prerequisites
- Ruby 3.3.6
- PostgreSQL
- Bundler

### Installation

```bash
# Install dependencies
bundle install

# Setup database
bin/rails db:create db:migrate

# Start development server
bin/dev
# or
bin/rails server

# Visit http://localhost:3000
```

### Sync Data

```bash
# Sync all agencies (background job)
bin/rails runner "SyncAllAgenciesJob.perform_now"

# Or sync specific agency
bin/rails console
> agency = Agency.first
> SyncAgencyJob.perform_now(agency_data: {name: agency.name, ...}, sync_log_id: SyncLog.create!(...).id)
```

---

## Tech Stack

- **Framework**: Rails 8.1.1
- **Database**: PostgreSQL
- **Background Jobs**: SolidQueue
- **Caching**: SolidCache
- **UI**: Tailwind CSS, Chartkick
- **Deployment**: Render.com

---

## Key Metrics

- **Word Count per Agency**: Total regulatory word count
- **Historical Changes**: Snapshot-based change tracking
- **Checksum per Agency**: SHA256 for content verification
- **Restrictions Count** (Custom Metric): Binding constraint words (shall, must, may not, prohibited, required)

---

## API

MCP (Model Context Protocol) JSON-RPC 2.0 endpoint available at `/mcp`:
- `get_agency_stats` - Get statistics for a specific agency
- `list_agencies` - List agencies ranked by word count
- `search_regulations` - Search by CFR title/part

---

## Code Quality

- **~975 Ruby lines** (excluding tests, auto-generated files)
- Clean service-oriented architecture
- Memory-efficient streaming XML parsing
- Production-ready deployment

---

**For full details, see [SUBMISSION.md](SUBMISSION.md)**
