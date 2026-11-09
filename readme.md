# Bagaicha Villa – Restaurant Management System

## Project Overview

Bagaicha Villa is a restaurant management system prototype designed to support different restaurant operations through separate customer, staff, and administrator interfaces.

The project explores how web technologies and database systems can support restaurant ordering, billing, menu administration, inventory tracking, and customer engagement.

## Features

- Customer ordering interface
- Staff billing interface
- Administrator login interface
- Menu management
- Inventory management
- Sales auditing
- Customer social feed
- Appearance settings
- PostgreSQL database schema
- Role-based access policies using Supabase Row Level Security

## Technology Stack

- HTML
- CSS
- JavaScript
- Supabase Authentication
- PostgreSQL
- SQL

## Project Structure

| File | Purpose |
|---|---|
| `login.html` | Login interface |
| `login-live.html` | Supabase authentication interface |
| `customer-order.html` | Customer ordering |
| `customer-social.html` | Customer social interface |
| `staff-billing.html` | Staff billing |
| `admin-menu.html` | Menu administration |
| `admin-inventory.html` | Inventory management |
| `admin-sales-audit.html` | Sales audit |
| `admin-appearance.html` | Appearance settings |
| `schema.sql` | Database schema and security policies |

## Project Status

Prototype / Development

Some features may require further implementation, integration, and testing before production use.

## Security Notes

- Do not commit private API keys, service-role keys, passwords, or environment files.
- Configure and test database security policies before deployment.
- Use Supabase Authentication for account management.

## Future Improvements

- Complete frontend and backend integration
- Improve authentication and role-based access
- Implement order and payment workflows
- Test inventory automation
- Add responsive design and accessibility improvements
- Add documentation and application screenshots