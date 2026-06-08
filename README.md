# Multi-Branch POS Rebuild

This project has been reset to a clean, module-by-module build. The current code contains:

- **Module 1: Dashboard**
- **Login/Auth Foundation**
- **Module 2: Branch Management**
- **Module 3: User & Role Management**
- **Module 4: Product Management**
- **Module 5: Inventory Management**
- **Module 6: Stock Transfer**
- **Module 7: POS Sales / Checkout**
- **Module 8: Philippines Invoice / BIR Compliance**
- **Module 9: Tax Management**
- **Module 10: Senior Citizen & PWD Discounts**
- **Module 11: Payments**
- **Module 12: Cash Register / Shift Management**
- **Module 13: Returns & Exchanges**
- **Module 14: Purchase Management**
- **Module 15: Supplier Management**
- **Module 16: Customer Management**
- **Module 17: Expenses**
- **Module 18: Accounting**
- **Module 19: Reports**
- **Module 20: Audit Logs**
- **PWA install support**

## What Is Included

Module 1 Dashboard:
- Sales by branch
- Daily sales summary
- Cashier performance
- Low stock alerts
- Responsive dashboard layout
- Fresh sample business data for testing
- Role-aware dashboard metrics

Login/Auth Foundation:
- Username/password login
- Secure first-admin setup
- Protected routes
- Profile lookup for signed-in users

Module 2 Branch Management:
- Head office and branch setup
- Branch code
- BIR RDO code/name
- Legal name, TIN, business style
- Branch-wise pricing mode
- Branch-wise tax profile and VAT rate
- Branch-wise inventory control setting
- Branch status enable/disable
- Admin hard delete for clean/test branches with no business history
- Branch summary counts for stock and assigned users

Module 3 User & Role Management:
- Admin, manager, cashier, and auditor roles
- Admin-created staff using username and password
- Branch-level access
- Permission checklists
- Shift days and shift time windows
- Open/close shift permissions
- Max discount percentage per user
- Activity logs for user access changes
- Admin permanent-delete controls for staff accounts

Module 3 keeps staff creation and permanent deletion protected so secret administrator credentials are never exposed to regular users.

Module 4 Product Management:
- Products, categories, brands, and units
- SKU and barcode fields
- Product variants with their own SKU/barcode/pricing
- VATable, VAT-exempt, zero-rated, and non-VAT tagging
- Cost price, selling price, reorder level, and active catalog status
- Admin-only create, edit, and product delete controls
- Responsive product catalog screen

Module 5 Inventory Management:
- Branch-wise stock tracking
- Batch numbers and expiry dates
- Stock in, stock out, adjustment plus/minus
- Damaged and expired stock removal
- Reorder level and low-stock visibility
- Batch expiry watch with 30-day alerts
- Movement history
- Physical stock count posting with automatic variance adjustments

Module 6 Stock Transfer:
- Branch-to-branch transfer requests
- Source branch approval
- FEFO dispatch from source batches
- Destination branch receiving
- Received quantity variance tracking
- Transfer ledger with searchable status history
- Inventory movements for transfer in and transfer out

Module 7 POS Sales / Checkout:
- Barcode and SKU scanning support
- Fast product search
- Responsive cashier checkout screen
- Discounts with user permission and max-percent checks
- VAT calculation from product tax tags
- Multiple and split payment methods
- Invoice/receipt saving and printing
- Offline sale queue with manual sync
- FEFO stock reduction after checkout
- Recent invoice history and reprint view

Module 8 Philippines Invoice / BIR Compliance:
- POS/CRM machine registration details by branch
- Machine serial number, MIN, permit, accreditation, and software details
- Sales Invoice, Cash Invoice, Charge/Credit Invoice, Service Invoice, and Billing Invoice document types
- Branch/machine invoice serial numbering with prefix, digit padding, start/current/end controls
- Automatic invoice number assignment during checkout
- Reprint logging with reason and copy count
- Invoice voiding with reason, stock reversal, and audit log entry
- Z-reading lock that blocks same-day voids after final reading
- X-reading and Z-reading summaries by branch, machine, and business date

Module 9 Tax Management:
- VAT-registered, non-VAT/percentage-tax, and mixed tax profiles
- Configurable 12% VAT defaults and branch percentage tax rates
- Branch tax profile assignment
- Tax-inclusive or tax-exclusive branch defaults
- VATable, VAT-exempt, zero-rated, non-VAT, and percentage-tax codes
- BIR tax report lines from completed POS sales
- Branch tax comparison charts
- Product tax-tagging summary

Module 10 Senior Citizen & PWD Discounts:
- 20% Senior/PWD discount setup
- VAT exemption tracking for eligible VATable items
- 5% special discount category for basic necessities or prime commodities
- OSCA/PWD ID, beneficiary name, invoice number, and discount amount capture
- Product-level Senior/PWD eligibility tagging
- Branch-level Senior/PWD settings
- Checkout Senior/PWD claim creation
- Separate Senior/PWD report page with daily and branch charts

Module 11 Payments:
- Cash, credit/debit card, GCash, Maya, bank transfer, store credit, and COD methods
- Branch-level payment method enable/disable
- Reference number requirements for non-cash methods
- Split payment reporting
- Tendered, applied, change, processor fee, and net payment tracking
- Payment settlement status updates
- POS payment dropdown from branch-enabled method setup
- Payments dashboard with method, branch, and daily charts

Module 12 Cash Register / Shift Management:
- Branch cash register setup with default register seeding
- Opening cash per cashier shift
- Cash in and cash out drawer movement tracking
- POS sales automatically attached to the cashier's open shift
- Shift closing with counted cash
- Expected cash and short/over tracking
- End-of-day branch, cashier, and movement reports
- POS checkout warning when no open shift exists

Module 13 Returns & Exchanges:
- Sales return processing from saved invoices
- Cash/card/wallet/bank/store-credit refund tracking
- Exchange credit and credit memo issuance
- Invoice void workflow through the existing BIR void routine
- Return reason tracking
- Returned-item condition and disposition tagging
- Sellable returns restored to inventory using original batch traceability
- Returns dashboard with branch and daily charts

Module 14 Purchase Management:
- Supplier quick setup for purchasing
- Purchase order creation, submit, approve, cancel, and receiving flow
- Goods received notes posted into branch inventory batches
- Supplier invoice/payable tracking with pending, partial, paid, and voided states
- Purchase returns that reduce the original received batch stock
- Cost history updates from received items
- Purchasing dashboard with daily receiving and branch comparison charts

Module 15 Supplier Management:
- Supplier profiles with terms, credit limits, contacts, TIN, account details, status, and default payment method
- Supplier payables dashboard with overdue invoice tracking
- Supplier payment ledger with posted and voided states
- Supplier payments applied to invoices and automatic invoice balance/status updates
- Purchase history by supplier from goods received notes
- Branch payable comparison and daily supplier payment charts

Module 16 Customer Management:
- Customer profiles with type, contact details, TIN, branch, credit limit, and status
- POS customer selector with automatic customer purchase history linking
- Customer purchase history from completed invoices
- Customer receivables and store-credit ledger
- COD/customer-credit sales automatically tracked as receivables
- Loyalty points earned from completed POS invoices
- Manual customer payments, write-offs, store-credit entries, and loyalty adjustments

Module 17 Expenses:
- Branch expenses for rent, utilities, salaries, supplies, repairs, transport, marketing, and miscellaneous costs
- Expense category setup
- Draft, submitted, approved, rejected, paid, and voided expense states
- Approval, rejection, paid marking, and void controls with activity logs
- Branch, category, and daily expense reporting charts
- Admin all-branch view and manager branch-only scope

Module 18 Accounting:
- Chart of accounts for cash, receivables, inventory, VAT, payables, revenue, COGS, expenses, and adjustments
- Sales journal from completed POS invoices
- Cash ledger from sale payments, customer payments, supplier payments, and paid expenses
- Accounts receivable from customer balances
- Accounts payable from open supplier invoices
- Profit/loss report with sales revenue, COGS, gross profit, operating expenses, and net profit
- VAT payable report from output VAT less purchase and expense input VAT
- Trial balance view with operational balances and posted manual journal adjustments
- Balanced manual journals with debit/credit validation and void controls

Module 19 Reports:
- Daily sales report showing only dates with completed sales
- Branch sales and branch performance comparison
- Cashier sales and average order reporting
- Sales invoice detail with FEFO COGS and gross profit
- Inventory report with branch stock, reorder, expiry, and stock value
- Stock movement report
- VAT sales report by tax type
- Senior/PWD discount report
- Z-reading report
- Profit report by branch
- CSV export from the active report view

Module 20 Audit Logs:
- Central audit trail from system activity logs
- Login/logout history
- Void, deleted-record, and high-risk event review
- Product and variant price-change audit triggers
- Discount audit from completed sales
- Stock adjustment, damaged, and expired movement audit
- Branch-scoped visibility for managers
- CSV export from the active audit view

PWA Install Support:
- Installable app experience for desktop, tablet, and mobile browsers
- App icons for normal and maskable home-screen display
- App shell caching after the first production load
- Automatic app-shell updates after a new deployment
- Live sales and inventory requests stay online-first to avoid stale business data

## Step 1: Create A New Supabase Project

1. Open [Supabase](https://supabase.com/dashboard).
2. Click **New project**.
3. Enter your project name, database password, and region.
4. Wait until the project is fully ready.
5. Open **Project Settings > API**.
6. Copy:
   - **Project URL**
   - **anon public key**

## Step 2: Add Frontend Environment Variables

Create or update `.env` in this project root:

```env
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-public-key
VITE_CURRENCY=PHP
```

Restart the Vite server after changing `.env`.

## Step 3: Remove Old Supabase Tables

In Supabase, open **SQL Editor** and run:

```sql
-- paste everything from:
supabase/00-reset-public-schema.sql
```

Important: this deletes all tables, functions, policies, views, and data in the `public` schema.

It does not delete Supabase Auth users. If you also want those removed:

1. Go to **Authentication > Users**.
2. Delete the old users manually.

## Step 4: Install Module 1 Dashboard Schema

After the reset finishes, open a new SQL Editor query and run:

```sql
-- paste everything from:
supabase/01-dashboard-module.sql
```

This creates:

- `branches`
- `cashiers`
- `products`
- `branch_inventory`
- `sales_orders`
- `dashboard_get_metrics(...)`
- demo data for testing the dashboard immediately

## Step 5: Install Login + Module 2 Branch Management

After Module 1 finishes, open another SQL Editor query and run:

```sql
-- paste everything from:
supabase/02-auth-and-branch-management.sql
```

This creates:

- `user_profiles`
- `branch_settings`
- first-admin setup action
- branch management actions
- role-aware dashboard access
- safe branch hard-delete action

Important: after Module 2 is installed, continue with Module 3 before using the login page. Username login is installed by Module 3.

If you already installed Module 2 before branch hard delete was added, run this patch once:

```sql
-- paste everything from:
supabase/patch-branch-hard-delete.sql
```

## Step 6: Install Module 3 User & Role Management

Open another SQL Editor query and run:

```sql
-- paste everything from:
supabase/03-user-role-management.sql
```

This creates:

- `user_access_settings`
- `activity_logs`
- username login resolver
- user update actions
- activity log helpers

It also removes the old invite-code Module 3 objects if they exist.

If you already had users from the old email login version, the script creates usernames from the email name before `@`. For example, `admin@gmail.com` becomes `admin`. You can edit usernames later from **Users** after logging in as admin.

## Step 7: Deploy Staff Admin Edge Functions

First-admin creation, direct staff creation, and permanent staff deletion require Edge Functions:

- `admin-bootstrap-user`
- `admin-create-staff`
- `admin-delete-staff`

Deploy with Supabase CLI:

```bash
npx supabase functions deploy admin-bootstrap-user --project-ref your-project-ref --no-verify-jwt
npx supabase functions deploy admin-create-staff --project-ref your-project-ref --no-verify-jwt
npx supabase functions deploy admin-delete-staff --project-ref your-project-ref --no-verify-jwt
```

If your project is already linked:

```bash
npx supabase functions deploy admin-bootstrap-user --no-verify-jwt
npx supabase functions deploy admin-create-staff --no-verify-jwt
npx supabase functions deploy admin-delete-staff --no-verify-jwt
```

Important:

- Do not put `SUPABASE_SERVICE_ROLE_KEY` in `.env`, Vite, or Vercel frontend variables.
- Supabase Edge Functions normally receive `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` from Supabase automatically.
- If serving functions locally, create local function secrets for those values.

If a function URL returns `BOOT_ERROR`, redeploy the functions:

```bash
npx supabase functions deploy admin-bootstrap-user --project-ref your-project-ref --no-verify-jwt
npx supabase functions deploy admin-create-staff --project-ref your-project-ref --no-verify-jwt
npx supabase functions deploy admin-delete-staff --project-ref your-project-ref --no-verify-jwt
```

If Add Staff shows **Database error creating new user**, open SQL Editor and run:

```sql
-- paste everything from:
supabase/patch-auth-user-trigger.sql
```

Then redeploy `admin-create-staff` and try Add Staff again. This fixes the new-user trigger that creates the staff profile when a login account is created.

## Step 8: Install Module 4 Product Management

Open another SQL Editor query and run:

```sql
-- paste everything from:
supabase/04-product-management.sql
```

This creates:

- `product_categories`
- `product_brands`
- `product_units`
- `product_variants`
- product tax/pricing columns
- product management actions
- product category, brand, and unit actions

Run this after Module 3, because it uses the active-user, admin-check, and activity-log functions from the login/user modules.

## Step 9: Install Module 5 Inventory Management

Open another SQL Editor query and run:

```sql
-- paste everything from:
supabase/05-inventory-management.sql
```

This creates:

- `inventory_batches`
- `inventory_movements`
- `stock_counts`
- `stock_count_items`
- inventory management actions
- batch/expiry seed records from existing Module 1 stock
- product and inventory permission entries for staff roles

Run this after Module 4. It keeps `branch_inventory` synchronized so the dashboard and product module continue to show accurate branch totals.

## Step 10: Install Module 6 Stock Transfer

Open another SQL Editor query and run:

```sql
-- paste everything from:
supabase/06-stock-transfer.sql
```

This creates:

- `stock_transfers`
- `stock_transfer_items`
- `stock_transfer_batches`
- stock transfer management actions
- transfer permissions for admin, manager, and auditor roles
- transfer movement support in `inventory_movements`

Run this after Module 5. Dispatch uses FEFO from `inventory_batches`, receiving creates new destination batches, and both sides keep `branch_inventory` synchronized.

## Step 11: Install Module 7 POS Sales / Checkout

Open another SQL Editor query and run:

```sql
-- paste everything from:
supabase/07-pos-sales-checkout.sql
```

This creates:

- `sales_order_items`
- `sales_order_payments`
- `sales_order_batch_allocations`
- POS checkout actions
- invoice number fields on `sales_orders`
- cashier/user linking for sales reporting
- dashboard sales/cashier reporting updates for real POS orders

Run this after Module 6. Checkout reduces source branch stock immediately using FEFO batches and saves item, payment, tax, invoice, and batch allocation detail.

## Step 12: Install Module 8 Philippines Invoice / BIR Compliance

Open another SQL Editor query and run:

```sql
-- paste everything from:
supabase/08-bir-compliance.sql
```

This creates:

- `bir_pos_machines`
- `bir_invoice_series`
- `bir_invoice_reprint_logs`
- `bir_readings`
- invoice document type fields on `sales_orders`
- automatic branch/machine invoice serial assignment
- BIR compliance management controls
- X-reading and Z-reading generation
- invoice reprint and void controls

Run this after Module 7. The script creates one default POS/CRM machine and one default Sales Invoice series for each active branch so checkout can continue immediately. Replace the seeded permit, MIN, serial, and authority-to-print details with your real registered values before live use.

## Step 13: Install Module 9 Tax Management

Open another SQL Editor query and run:

```sql
-- paste everything from:
supabase/09-tax-management.sql
```

This creates:

- `tax_profiles`
- `tax_codes`
- branch tax profile fields on `branch_settings`
- tax management actions
- VATable, VAT-exempt, zero-rated, non-VAT, and percentage-tax report summaries
- `tax.view` and `tax.manage` permission entries

Run this after Module 8. The script seeds VAT 12%, non-VAT/percentage-tax, and mixed branch profiles, plus default product tax codes. Rates are configurable, so confirm your live tax profile and reporting setup with your accountant before production use.

## Step 14: Install Module 10 Senior Citizen & PWD Discounts

Open another SQL Editor query and run:

```sql
-- paste everything from:
supabase/10-senior-pwd-discounts.sql
```

This creates:

- `senior_pwd_discount_settings`
- `senior_pwd_discount_claims`
- Senior/PWD discount columns on `sales_orders` and `sales_order_items`
- product Senior/PWD eligibility tagging
- Senior/PWD management actions
- POS checkout Senior/PWD discount and claim handling
- `senior_pwd.view`, `senior_pwd.manage`, and `senior_pwd.apply` permission entries

Run this after Module 9. Rates are configurable per branch. Confirm final Senior Citizen, PWD, VAT exemption, booklet, and reporting rules with your accountant or compliance adviser before live use.

## Step 15: Install Module 11 Payments

Open another SQL Editor query and run:

```sql
-- paste everything from:
supabase/11-payments.sql
```

This creates:

- `payment_methods`
- `branch_payment_methods`
- tendered, change, fee, net, reference, and settlement columns on `sales_order_payments`
- branch-enabled payment method settings
- POS payment method options from branch setup
- payment validation triggers
- payment management actions
- `payments.view`, `payments.manage`, and `payments.settle` permission entries

Run this after Module 10. The script seeds Cash, Card, GCash, Maya, Bank transfer, Store credit, and COD. Non-cash methods can require references, and only cash/change-enabled methods can create change from overpayment.

## Step 16: Install Module 12 Cash Register / Shift Management

Open another SQL Editor query and run:

```sql
-- paste everything from:
supabase/12-cash-register-shifts.sql
```

This creates:

- `cash_registers`
- `cashier_shifts`
- `cash_drawer_movements`
- `shift_id` linkage on `sales_orders`
- shift opening, cash movement, closing, and report actions
- POS shift status check
- checkout rule that requires an open shift before completed POS checkout

Run this after Module 11. The script creates a default **REG-01 / Main Register** for each active branch. Existing sales stay unchanged; new POS sales are linked to the signed-in cashier's open shift.

## Step 17: Install Module 13 Returns & Exchanges

Open another SQL Editor query and run:

```sql
-- paste everything from:
supabase/13-returns-exchanges.sql
```

This creates:

- `return_reasons`
- `sales_returns`
- `sales_return_items`
- `sales_return_batch_allocations`
- `credit_memos`
- `sales_refunds`
- return tracking fields on `sales_orders`
- return processing and return dashboard actions
- `returns.view`, `returns.manage`, and `returns.approve` permission entries

Run this after Module 12. Sellable returns are restored to inventory with original batch traceability. Void transactions use the existing BIR void checks, including the posted Z-reading lock.

## Step 18: Install Module 14 Purchase Management

Open another SQL Editor query and run:

```sql
-- paste everything from:
supabase/14-purchase-management.sql
```

This creates:

- `suppliers`
- `purchase_orders`
- `purchase_order_items`
- `purchase_receipts`
- `purchase_receipt_items`
- `supplier_invoices`
- `purchase_returns`
- `purchase_return_items`
- `product_cost_history`
- purchase order, receiving, invoice status, supplier save, and purchase return actions
- `purchases.view`, `purchases.manage`, `purchases.approve`, and `purchases.receive` permission entries

Run this after Module 13. Receiving creates inventory batches, posts `stock_in` movements, updates product cost price, and keeps `branch_inventory` synchronized. Purchase returns reduce the linked received batch and post `stock_out` movements.

## Step 19: Install Module 15 Supplier Management

Open another SQL Editor query and run:

```sql
-- paste everything from:
supabase/15-supplier-management.sql
```

This creates:

- `supplier_payments`
- extra supplier profile fields for account, website, lead time, rating, status, and default payment method
- supplier profile save action
- supplier payment post and void actions
- supplier management dashboard data
- `suppliers.view`, `suppliers.manage`, and `suppliers.pay` permission entries

Run this after Module 14. Supplier payments update supplier invoice balances automatically. Voiding a posted supplier payment reverses the paid amount from the linked invoice and records the void in activity logs.

## Step 20: Install Module 16 Customer Management

Open another SQL Editor query and run:

```sql
-- paste everything from:
supabase/16-customer-management.sql
```

This creates:

- `customers`
- `customer_account_entries`
- `customer_loyalty_ledger`
- `customer_loyalty_settings`
- `customer_id` linkage on `sales_orders`
- POS customer option list
- customer dashboard, profile, account-entry, void-entry, and loyalty-adjustment actions
- `customers.view`, `customers.manage`, `customers.credit`, and `customers.loyalty` permission entries

Run this after Module 15. Existing POS sales still work. New POS sales with a customer name are linked to a customer profile automatically, and COD sales for linked customers create receivable entries.

## Step 21: Install Module 17 Expenses

Open another SQL Editor query and run:

```sql
-- paste everything from:
supabase/17-expenses.sql
```

This creates:

- `expense_categories`
- `expenses`
- seeded categories for rent, utilities, salaries, supplies, maintenance, transport, marketing, and miscellaneous expenses
- expense dashboard, category save, expense save, and status update actions
- `expenses.view`, `expenses.manage`, and `expenses.approve` permission entries

Run this after Module 16. Managers are locked to their own branch expenses, admins can see all branches, and auditors can view reports without posting changes.

## Step 22: Install Module 18 Accounting

Open another SQL Editor query and run:

```sql
-- paste everything from:
supabase/18-accounting.sql
```

This creates:

- `accounting_accounts`
- `accounting_journal_entries`
- `accounting_journal_lines`
- seeded chart of accounts
- accounting dashboard, report, manual-journal, and journal-void actions
- `accounting.view`, `accounting.manage`, and `accounting.close` permission entries

Run this after Module 17. Admins can view and post accounting journals for all branches. Managers and auditors can view accounting reports for their allowed branch scope unless you explicitly grant additional accounting permissions.

## Step 23: Install Module 19 Reports

Open another SQL Editor query and run:

```sql
-- paste everything from:
supabase/19-reports.sql
```

This creates:

- report permission helpers
- report data loader
- daily sales, branch sales, cashier sales, inventory, stock movement, VAT, Senior/PWD, Z-reading, and profit report datasets
- CSV export rows from the active report view

Run this after Module 18. Admins and auditors can report across active branches. Managers are locked to their assigned branch.

## Step 24: Install Module 20 Audit Logs

Open another SQL Editor query and run:

```sql
-- paste everything from:
supabase/20-audit-logs.sql
```

This creates:

- audit classifications and severity on `activity_logs`
- audit dashboard data loader
- login/logout audit recorder
- product and variant price-change audit triggers
- branch-scoped audit visibility for managers
- audit report datasets for login history, voids, deletes, discounts, stock adjustments, and price changes

Run this after Module 19. Admins and auditors can view system-wide audit logs. Managers can view audit records scoped to their branch.

## Step 25: Create Your First Admin Login

1. Start the app.
2. Open `http://localhost:5173/login`.
3. Click **Create first admin**.
4. Enter full name, username, and password.
5. Click **Create first admin**.

Only the first admin can be created this way. After one active admin exists, the bootstrap function refuses to create another admin.

## Step 26: Add Staff With Username And Password

1. Login as admin.
2. Open **Users** from the sidebar.
3. Click **Add staff**.
4. Enter full name, username, password, role, branch, permissions, and shift access.
5. Save.
6. The staff member can login directly with that username and password.

No invite code is required for this flow.

## Step 27: Manage Products

1. Login as admin.
2. Open **Products** from the sidebar.
3. Add or edit categories, brands, and units first.
4. Click **Add product**.
5. Enter SKU, barcode, product name, category, brand, unit, pricing, tax type, VAT rate, and reorder level.
6. Add variants when the same product has multiple sizes, packs, box quantities, or alternate barcodes.
7. Save.

Managers and auditors can view the catalog. Product creation, editing, and deletion are admin-only.

## Step 28: Manage Inventory

1. Login as admin or branch manager.
2. Open **Inventory** from the sidebar.
3. Use **Stock in** to receive product batches into a branch.
4. Use **Stock out** for manual outbound movement.
5. Use **Damaged/expired** to remove unsellable stock.
6. Use **Stock count** to post counted quantities. The system automatically creates adjustment movements for variance.
7. Review low-stock status, batch expiry, movement history, and posted stock counts.

Admins can manage all branches. Branch managers can manage only their own branch. Auditors can view inventory but cannot post movements.

## Step 29: Manage Stock Transfers

1. Login as admin or branch manager.
2. Open **Transfers** from the sidebar.
3. Click **New transfer**.
4. Select source branch, destination branch, product, variant if needed, and requested quantity.
5. Save the request.
6. Source branch admin/manager approves the request.
7. Source branch admin/manager dispatches the transfer. Stock decreases immediately from source batches using FEFO.
8. Destination branch admin/manager receives the transfer. Enter actual received quantities to record shortage variance.
9. Review the selected transfer panel for request, approval, dispatch, receive timestamps, batch lines, and variance.

Admins can operate all branches. Branch managers can create transfers involving their branch and can approve/dispatch only when their branch is the source. They can receive only when their branch is the destination. Auditors can view the transfer ledger.

## Step 30: Use POS Sales / Checkout

1. Login as admin, branch manager, or cashier.
2. Open **POS** from the sidebar.
3. Select the branch if you are admin. Managers and cashiers are locked to their assigned branch.
4. Select a saved customer profile or enter a walk-in customer name.
5. Scan a barcode/SKU or search for a product.
6. Add products to the cart and adjust quantities.
7. Apply a discount only if the signed-in user has discount permission and the discount is within their max percent.
8. Add one or more payment rows: Cash, Card, GCash, Maya, Bank transfer, Store credit, or COD.
9. Click **Checkout**.
10. The system saves the invoice, payment detail, sale items, customer link, and FEFO batch allocation, then reduces stock immediately.
11. Click **Print / Save PDF** in the receipt dialog to print or save the browser receipt as PDF.

Offline mode:

1. Build the cart as usual.
2. Click **Save offline** if the internet is down or the branch needs to queue the sale.
3. When online again, open **POS** and click **Sync now** on the offline warning.
4. Synced offline sales are submitted and stock is reduced at sync time.

## Step 31: Use BIR Compliance

1. Login as admin or branch manager.
2. Open **BIR** from the sidebar.
3. Review the default POS/CRM machine created for each active branch.
4. Edit each machine and enter the real machine serial number, MIN, accreditation number, permit number, software version, and permit dates.
5. Review invoice series for each branch/machine.
6. Edit the prefix, current number, end number, digit padding, and authority-to-print details to match your approved invoice booklet or POS permit setup.
7. Use **Generate reading** to create an X-reading during the day or a Z-reading for final end-of-day reporting.
8. Use the invoice table to log reprints with a reason.
9. Use the void action only before the same branch/date/machine has a Z-reading. Voiding reverses the FEFO stock allocations saved during checkout.

This module gives the system controls needed for Philippine invoice numbering and reading workflows, but it is not legal certification. Confirm final invoice layout, serial registrations, and permit details with your accountant or BIR-accredited POS provider before production use.

## Step 32: Use Tax Management

1. Login as admin.
2. Open **Tax** from the sidebar.
3. Select the report date range and branch.
4. Review gross sales, VATable sales, output VAT, percentage tax, total tax due, and completed order count.
5. Use the branch setup table to assign each branch a tax profile.
6. Use **Add profile** to create custom VAT, non-VAT, or mixed tax profiles.
7. Use **Add tax code** to maintain VATable, VAT-exempt, zero-rated, non-VAT, and percentage-tax codes.
8. Managers and auditors can view tax reports for their allowed branch scope, but setup edits are admin-only.

## Step 33: Use Senior Citizen & PWD Discounts

1. Login as admin.
2. Open **Senior/PWD** from the sidebar.
3. Review branch setup and edit the standard 20% rate, 5% basic goods rate, ID capture rule, booklet rule, and active status.
4. Search products and tag each item as **20% discount + VAT exemption**, **5% basic necessities / prime goods**, or **Not eligible**.
5. Open **POS**, add items to the cart, and choose **Senior Citizen** or **PWD** in the checkout panel.
6. Enter beneficiary name, ID type, ID number, and booklet/reference when required.
7. Checkout saves the invoice plus a Senior/PWD claim record automatically.
8. Return to **Senior/PWD** to review daily charts, branch comparison, claim totals, and saved claim records.

Admins can edit branch settings and product eligibility. Managers and auditors can view reports for their allowed branch scope.

## Step 34: Use Payments

1. Login as admin.
2. Open **Payments** from the sidebar.
3. Review collected, tendered, change, processor fee, net payment, and split order totals.
4. Edit standard payment methods to set reference requirements, fee rates, settlement days, and active status.
5. Use branch payment access to enable or disable methods per branch.
6. Open **POS** and select Cash, Card, GCash, Maya, Bank transfer, Store credit, or COD from the payment rows.
7. Add more rows for split payments.
8. Enter required reference numbers for non-cash methods.
9. Use the recent payment table to update settlement status when card, wallet, bank, or delivery payments clear.

Admins can edit payment setup. Managers can view their branch payment reports and update settlement status for their branch. Auditors can view payment reports.

## Step 35: Use Cash Register / Shifts

1. Login as admin, branch manager, or cashier.
2. Open **Shifts** from the sidebar.
3. Click **Open shift**.
4. Select branch/register, enter opening cash, and save.
5. Open **POS** and complete sales. Each completed sale is linked to your open shift automatically.
6. Return to **Shifts** and use **Cash in/out** for drawer additions or removals.
7. At the end of the shift, click **Close shift** and enter counted cash.
8. Review expected cash, counted cash, short/over amount, movement history, and branch charts.

Admins can see all branches. Managers see their assigned branch. Cashiers see and operate their own shift. Auditors can view reports only.

## Step 36: Use Returns & Exchanges

1. Login as admin, branch manager, or cashier.
2. Open **Returns** from the sidebar.
3. Find the original invoice in **Sales available for return**.
4. Click the return icon to process a refund, exchange credit, or credit memo.
5. Select the return reason, refund method, returned quantities, item condition, and disposition.
6. Use **Return to stock** only for sellable items. Damaged, expired, and write-off returns are recorded but not added back to active stock.
7. Click **Complete return**.
8. Review the return ledger, credit memo table, daily chart, and branch summary.
9. Use the void icon only for valid invoice voids before a posted Z-reading.

Admins can process all branches and void invoices. Managers can process their branch and void only when authorized. Cashiers can process branch returns when permitted. Auditors can view reports only.

## Step 37: Use Purchase Management

1. Login as admin or branch manager.
2. Open **Purchases** from the sidebar.
3. Click **Supplier** to create or edit a purchasing supplier.
4. Click **New PO**, select branch, supplier, products, quantities, costs, tax rate, and expected date.
5. Save the PO, then submit or approve it from the PO table.
6. Click the truck icon to receive an approved or submitted PO.
7. Enter supplier invoice number, receipt date, batch number, expiry date, received quantity, and unit cost.
8. Click **Post receiving**. The system creates a GRN, supplier invoice, inventory batch, stock movement, and cost history entry.
9. Use the supplier invoice table to mark payables pending, partial, paid, or voided.
10. Use the GRN return action to return supplier stock. Purchase returns reduce the linked received batch.

Admins can manage all branches. Managers can manage their assigned branch. Auditors can view purchase reports only.

## Step 38: Use Supplier Management

1. Login as admin or branch manager.
2. Open **Suppliers** from the sidebar.
3. Use the filters to select date range, branch, supplier, or search text.
4. Click **Supplier** to add or edit supplier profile details, payment terms, default payment method, credit limit, lead time, and status.
5. Review **Payables** to see pending, partial, paid, voided, and overdue supplier invoices.
6. Click the wallet icon on an invoice to post a supplier payment against that invoice.
7. Click **Payment** to post an advance supplier payment without a linked invoice.
8. Review the **Payment ledger** for posted and voided supplier payments.
9. Use the ban icon to void a posted supplier payment. The system reverses the paid amount from the linked invoice and saves the void reason.
10. Review **Purchase history** to see goods received notes by supplier.

Admins can manage and pay suppliers for all branches. Managers can manage and pay suppliers only for their assigned branch. Auditors can view supplier reports only.

## Step 39: Use Customer Management

1. Login as admin, branch manager, cashier, or auditor.
2. Open **Customers** from the sidebar.
3. Use the filters to select date range, branch, customer, or search text.
4. Click **Customer** to add or edit customer profile details, type, phone, email, TIN, address, branch, credit limit, and status.
5. Open **POS** and select a saved customer before checkout. The completed invoice appears in customer purchase history.
6. Use **COD** for a linked customer sale when the sale should become a receivable.
7. Click **Credit / payment** to post a customer charge, payment, store-credit issue/use, return credit, or write-off.
8. Review the **Account ledger** for receivable and store-credit movement.
9. Use the ban icon to void a posted manual customer ledger entry.
10. Click the star icon to adjust loyalty points when an authorized correction is needed.
11. Review customer sales charts, top customers, branch summary, and loyalty ledger.

Admins can manage all customers and balances. Managers can manage customers and balances for their assigned branch. Cashiers can view customer records and select customers at POS. Auditors can view customer reports only.

## Step 40: Use Expenses

1. Login as admin or branch manager.
2. Open **Expenses** from the sidebar.
3. Use the filters to select date range, branch, or search text.
4. Click **Expense** to add rent, utilities, salary, supply, maintenance, transport, marketing, or other branch expenses.
5. Save the expense as **Draft** or **Submit for approval**.
6. Use the check icon to approve a submitted expense.
7. Use the card icon to mark an approved expense as paid.
8. Use the reject or void icons only with a written reason.
9. Admins can click **Category** to add or update expense categories.
10. Review daily expense charts, category charts, and branch summaries.

Admins can manage and approve expenses for all branches. Managers can manage and approve only their assigned branch. Auditors can view expense reports only.

## Step 41: Use Accounting

1. Login as admin, branch manager, or auditor.
2. Open **Accounting** from the sidebar.
3. Use the filters to select date range, branch, or search text.
4. Review sales revenue, COGS, gross profit, expenses, net profit, cash net, receivables, and VAT payable cards.
5. Review daily net profit and branch performance charts.
6. Check the **Sales journal** for completed invoices and FEFO cost.
7. Check the **Cash ledger** for sale payments, customer payments, supplier payments, and paid expenses.
8. Review open customer receivables and supplier payables.
9. Review the VAT payable report and trial balance.
10. Admins can click **Manual journal** to post balanced debit/credit adjustments.
11. Admins can void posted manual journals with a written reason.

Admins can view and manage accounting for all branches. Managers and auditors can view their allowed branch scope. Manual journals are admin-only unless you grant `accounting.manage` or `accounting.close` to a manager.

## Step 42: Use Reports

1. Login as admin, branch manager, or auditor.
2. Open **Reports** from the sidebar.
3. Select date range, branch, report type, and optional search text.
4. Use **Overview** for daily sales, branch sales, cashier performance, and profit charts.
5. Use **Sales** for daily sales, branch sales, cashier sales, invoice detail, top products, and payment mix.
6. Use **Inventory** for branch stock, low-stock status, stock value, expiry status, stock movement, and slow-moving products.
7. Use **VAT** for VATable, VAT-exempt, zero-rated, and non-VAT sales totals.
8. Use **Senior/PWD** for beneficiary, ID, invoice, discount, and VAT-exempt records.
9. Use **Z-reading** for posted end-of-day machine readings.
10. Use **Profit** for revenue, FEFO COGS, expenses, and net profit by branch.
11. Click **Export CSV** to download the active report rows.

Daily report charts only show dates with actual records. Admins and auditors can view all allowed branches. Managers are locked to their assigned branch.

## Step 43: Use Audit Logs

1. Login as admin, branch manager, or auditor.
2. Open **Audit Logs** from the sidebar.
3. Select date range, branch, actor, category, severity, and optional search text.
4. Use **Overview** for daily audit charts, category charts, and the latest event trail.
5. Use **Access** for login/logout history.
6. Use **Controls** for voided records, deleted records, and price changes.
7. Use **Discounts** for sales invoices where discounts were applied.
8. Use **Inventory** for stock adjustment, damaged, and expired stock movements.
9. Click **Export CSV** to download the active audit section.

Admins and auditors can review all branches. Managers can review audit records for their assigned branch.

## Step 44: Hard Delete Staff

1. Login as admin.
2. Open **Users**.
3. Click the red trash icon on a staff row.
4. Confirm permanent deletion.

Hard delete removes:

- staff login account
- `user_profiles` row
- `user_access_settings` row

The app blocks deleting your own admin account and blocks deleting the last active admin.

## Step 45: Run The App

Install dependencies if needed:

```bash
npm install
```

Start the local app:

```bash
npm run dev
```

Open:

```text
http://localhost:5173
```

## Step 46: Verify Dashboard, Branch, User, Product, Inventory, Transfer, POS, BIR, Tax, Senior/PWD, Payments, Shifts, Returns, Purchases, Suppliers, Customers, Expenses, Accounting, Reports, And Audit Logs Modules

After login you should see:

- total sales
- completed orders
- average order
- VAT tracked
- discount total
- low-stock count
- sales by branch chart
- daily sales chart
- cashier performance table
- low-stock alert table
- branch management navigation
- branch list
- add/edit branch dialog
- branch pricing/tax/inventory settings
- branch enable/disable action
- safe hard-delete action for clean/test branches
- users navigation
- user directory
- add staff dialog with username and password
- role and permission assignment
- shift access controls
- activity logs
- products navigation
- product catalog table
- product search and category/tax filters
- add/edit product dialog
- variant entry rows
- category, brand, and unit setup sections
- VATable, VAT-exempt, zero-rated, and non-VAT product tags
- inventory navigation
- branch-wise stock table
- stock in/out adjustment dialog
- damaged/expired stock posting
- expiry watch section
- batch stock ledger
- movement history table
- stock count dialog and posted stock count list
- transfers navigation
- transfer request form
- transfer approval, dispatch, receiving, and cancellation actions
- FEFO batch dispatch detail
- received quantity variance display
- POS navigation for admin, manager, and cashier
- barcode/SKU scan input
- product search and responsive product tiles
- cart quantity controls
- discount and split payment controls
- checkout receipt dialog
- recent invoice table
- offline sale queue and sync action
- BIR navigation for admin, manager, and auditor
- POS/CRM machine registry
- invoice serial number control
- reprint and void controls
- X-reading and Z-reading history
- Tax navigation for admin, manager, and auditor
- tax report date and branch filters
- VATable, VAT-exempt, zero-rated, and non-VAT sales summaries
- output VAT and percentage-tax summary cards
- branch tax setup table
- tax profile and tax code tables
- Senior/PWD navigation for admin, manager, and auditor
- branch Senior/PWD settings table
- product Senior/PWD eligibility tagging
- Senior/PWD daily and branch benefit charts
- saved Senior/PWD claim records
- POS Senior Citizen/PWD checkout panel
- OSCA/PWD beneficiary details on saved receipts
- Payments navigation for admin, manager, and auditor
- payment method setup table
- branch payment method enable/disable table
- payment method and branch collection charts
- recent payment transaction table
- settlement status update dialog
- POS reference-required payment validation
- cash/change-only overpayment validation
- Shifts navigation for admin, manager, cashier, and auditor
- open shift form with branch/register/opening cash
- current drawer status and expected cash panel
- cash in and cash out movement dialog
- close shift dialog with counted cash and short/over preview
- daily cash sales and branch drawer charts
- shift history table and cash drawer movement log
- POS checkout open-shift warning and checkout enforcement
- Returns navigation for admin, manager, cashier, and auditor
- eligible invoice search for sales returns
- return/refund/exchange/credit memo processing dialog
- returned quantity, condition, and disposition controls
- sellable return stock restoration through original batch allocations
- credit memo ledger
- return reason tracking
- daily returns and branch return charts
- POS recent invoice return/refund shortcut
- Purchases navigation for admin, manager, and auditor
- purchase order table with submit, approve, receive, and cancel actions
- supplier quick-create and payable summary
- goods received notes table
- supplier invoice status update dialog
- purchase return dialog for received batches
- purchase receiving and branch comparison charts
- cost history table from posted receiving
- Suppliers navigation for admin, manager, and auditor
- supplier profile form with terms, credit limit, account, status, and default payment method
- supplier payables table with overdue invoice highlighting
- supplier payment posting dialog
- supplier payment ledger with void action
- supplier payment and branch payable charts
- supplier purchase history from goods received notes
- Customers navigation for admin, manager, cashier, and auditor
- customer profile form with branch, type, contact, TIN, credit limit, and status
- POS customer selector
- customer purchase history from linked invoices
- customer receivables and store-credit ledger
- manual customer charge/payment/store-credit/write-off dialog
- loyalty points ledger and adjustment dialog
- customer sales, top customer, and branch summary charts
- Expenses navigation for admin, manager, and auditor
- expense form with branch, category, date, payee, amount, tax, payment method, and status
- expense category setup for admin
- draft, submit, approve, reject, paid, and void controls
- daily expense and category expense charts
- branch expense summary table
- Accounting navigation for admin, manager, and auditor
- accounting KPI cards for revenue, COGS, profit, cash, receivables, and VAT
- daily net profit and branch performance charts
- sales journal with invoice, branch, revenue, VAT, total, and FEFO COGS
- cash ledger for cash-equivalent inflows and outflows
- accounts receivable and accounts payable tables
- VAT payable panel
- trial balance table
- manual journal dialog with balanced debit/credit validation
- manual journal line viewer and void control
- Reports navigation for admin, manager, and auditor
- report filters for date range, branch, report type, and search
- daily sales chart and table showing only days with completed sales
- branch sales and cashier performance charts
- invoice sales detail with FEFO COGS and gross profit
- top products and payment mix reports
- inventory report with low-stock, stock value, expiry, and movement rows
- VAT sales report by tax type
- Senior/PWD discount report
- Z-reading report
- branch profit report
- CSV export for the active report
- Audit Logs navigation for admin, manager, and auditor
- audit filters for date range, branch, actor, category, severity, and search
- daily audit event chart and category chart
- activity log table with actor, branch, category, severity, and metadata
- login/logout history table
- void and deleted-record audit sections
- product and variant price-change audit records
- sales discount audit records
- stock adjustment, damaged, and expired movement audit records
- CSV export for the active audit view

If you see a missing function or schema cache error, run the SQL scripts again in this order:

1. `supabase/00-reset-public-schema.sql`
2. `supabase/01-dashboard-module.sql`
3. `supabase/02-auth-and-branch-management.sql`
4. `supabase/03-user-role-management.sql`
5. `supabase/04-product-management.sql`
6. `supabase/05-inventory-management.sql`
7. `supabase/06-stock-transfer.sql`
8. `supabase/07-pos-sales-checkout.sql`
9. `supabase/08-bir-compliance.sql`
10. `supabase/09-tax-management.sql`
11. `supabase/10-senior-pwd-discounts.sql`
12. `supabase/11-payments.sql`
13. `supabase/12-cash-register-shifts.sql`
14. `supabase/13-returns-exchanges.sql`
15. `supabase/14-purchase-management.sql`
16. `supabase/15-supplier-management.sql`
17. `supabase/16-customer-management.sql`
18. `supabase/17-expenses.sql`
19. `supabase/18-accounting.sql`
20. `supabase/19-reports.sql`
21. `supabase/20-audit-logs.sql`

Then refresh the browser.

## One SQL Patch For Daily Charts

If you only want to hide empty days from all daily charts without rerunning every module file, open Supabase **SQL Editor** and run:

```sql
-- paste everything from:
supabase/patch-daily-record-days-only.sql
```

This patch keeps your existing data and filters daily chart rows so only days with records are returned.

## Step 47: Build For Production

```bash
npm run build
```

## Step 48: Deploy To Vercel

1. Push the project to GitHub.
2. Import the repo in Vercel.
3. Add these Vercel environment variables:
   - `VITE_SUPABASE_URL`
   - `VITE_SUPABASE_ANON_KEY`
   - `VITE_CURRENCY`
4. Build command:

```bash
npm run build
```

5. Output directory:

```text
dist
```

## Step 49: Test PWA Install

For the fastest check during development:

```bash
npm run dev
```

Then open:

```text
http://localhost:5173/manifest.webmanifest
```

You should see the app manifest. Then open `http://localhost:5173`, refresh once, and check the browser install icon.

For the most accurate install test, use the production preview:

1. Build the app:

```bash
npm run build
```

2. Preview the production build:

```bash
npm run preview
```

3. Open the preview URL in Chrome or Edge.
4. Login once so the app shell loads.
5. Click the install icon in the browser address bar.
6. On mobile, open the deployed Vercel URL and choose **Add to Home Screen**.
7. After install, open the app from the desktop or home-screen icon.

Important:

- The installed app needs HTTPS in production. Vercel already provides HTTPS.
- Localhost is allowed for testing, but ordinary LAN URLs like `http://192.168.x.x` are not installable unless served with HTTPS.
- The app shell can load after the first successful visit.
- Live sales, checkout, stock, reports, and staff actions still need network access unless you use the POS offline queue.
- After a new deployment, the installed app updates its cached app shell automatically on the next visit.

## Next Module

Recommended next build order:

1. Payroll
2. Offline sync hardening
