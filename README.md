# Hire AI

AI-powered hiring assistant system.

## Project Structure
- `backend/`: Express.js backend API service.
- `ai-service/`: FastAPI Python service for AI/ML tasks.
- `database/`: Database schema and SQL migrations.

## Getting Started

### Backend Setup
1. `cd backend`
2. `npm install`
3. `cp .env.example .env`
4. `npm run dev`

### AI Service Setup
1. `cd ai-service`
2. `pip install -r requirements.txt`
3. `cp .env.example .env`
4. `uvicorn app.main:app --reload`
