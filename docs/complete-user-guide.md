# Multi-Branch POS Complete User Guide

Version: Modules 1 to 20

This guide explains how to use the complete system step by step. It also explains what the system does after each action, so admins, managers, cashiers, auditors, and inventory staff understand the full business flow.

## 1. System Purpose

The system is built for retail businesses that operate one or more branches. It helps the business manage:

- sales and checkout
- branch setup
- staff and permissions
- products, variants, prices, and taxes
- branch-wise inventory
- stock transfer
- invoice numbering and readings
- payment tracking
- cash drawer shifts
- returns and exchanges
- purchases and suppliers
- customers, credit, loyalty, and store credit
- expenses and accounting
- reports and audit logs

The system is branch-aware. This means every sale, stock movement, payment, expense, shift, and report is tied to the correct branch.

## 2. User Roles

Admin:

- controls all branches
- creates branches and staff
- manages products, prices, taxes, permissions, reports, accounting, and audit logs
- can delete allowed clean/test records where the system permits it

Branch Manager:

- manages only the assigned branch
- can manage branch stock, transfers, POS, reports, shifts, returns, purchases, suppliers, customers, expenses, and audit records for the assigned branch based on permission settings

Cashier:

- mainly uses POS checkout
- can process sales, payments, receipts, returns, and shift actions only when permissions allow
- sees branch-specific records only

Auditor:

- reviews reports, readings, stock, accounting, and audit logs
- normally cannot post changes

Inventory Staff:

- can manage stock counts, stock movements, receiving, transfers, and inventory tasks when granted permission

## 3. Login And Navigation

1. Open the app URL.
2. Enter username and password.
3. Click Login.
4. The system checks your account, role, branch assignment, active status, and permissions.
5. After login, the sidebar only shows pages that your role can access.
6. Admin users can usually see all branches.
7. Branch-level users are locked to their assigned branch.

If a page is missing from the sidebar, the signed-in user does not have permission for that module.

## 4. Daily Business Flow

Recommended daily flow:

1. Manager or cashier opens a shift.
2. Cashier enters opening cash.
3. Cashier sells products through POS.
4. The system saves invoices, payments, tax amounts, and stock allocation.
5. Stock decreases immediately from the earliest expiry batches first.
6. Cash payments update expected drawer cash.
7. Non-cash payments are tracked by method and reference.
8. Returns, voids, cash in, cash out, and expenses are recorded during the day.
9. Manager generates X-reading for checking during the day.
10. At closing, cashier counts cash and closes the shift.
11. Manager generates Z-reading when the business day is final.
12. Admin or manager reviews reports, accounting, and audit logs.

## 5. First Admin Setup

1. Open the login page.
2. If no admin exists, use the first-admin setup flow.
3. Enter the admin name, username, email, and password.
4. Save the admin account.
5. Login using the admin username and password.
6. Create branches before adding branch managers and cashiers.

How it works:

- The first admin becomes the main account owner.
- The admin can create other admins, managers, cashiers, auditors, and inventory staff.
- The system blocks removing the last active admin.

## 6. Module 1 - Dashboard

Purpose:

- gives a quick view of sales, orders, cashier performance, and low stock

Who uses it:

- admin
- branch manager
- auditor

How to use:

1. Open Dashboard from the sidebar.
2. Select date range.
3. Admin can select all branches or one branch.
4. Manager sees the assigned branch only.
5. Review sales totals, order counts, average order value, VAT, discounts, and low-stock count.
6. Review charts for daily sales and sales by branch.
7. Review cashier performance and low-stock tables.

How the system works:

- completed sales are counted in sales totals
- voided and refunded records are separated where applicable
- low-stock alerts compare stock against reorder levels
- managers only see their branch data

## 7. Module 2 - Branch Management

Purpose:

- creates and controls head office and branch records

Who uses it:

- admin
- branch manager with limited branch view

How to add a branch:

1. Open Branches.
2. Click Add Branch.
3. Enter branch name, branch code, address, legal name, TIN, business style, and BIR RDO details.
4. Choose pricing mode, tax profile, VAT rate, and inventory control setting.
5. Save.

How to update a branch:

1. Open Branches.
2. Click the edit action.
3. Update details.
4. Save.

How to disable a branch:

1. Open Branches.
2. Select the branch.
3. Use the status control.
4. Disable the branch.

How hard delete works:

- hard delete is allowed only for clean/test branches with no linked business history
- if the branch has sales, users, stock, batches, transfers, purchases, or expenses, the system blocks hard delete
- disabling is the safer option for real branches

How the system works:

- branch code helps identify the branch in reports and invoices
- branch settings control pricing, tax, inventory, users, payments, and reporting
- branch records are linked to sales, inventory, staff, shifts, purchases, suppliers, customers, expenses, and accounting

## 8. Module 3 - User And Role Management

Purpose:

- creates staff accounts and controls what each staff member can do

Who uses it:

- admin
- auditor for review if allowed

How to add staff:

1. Open Users.
2. Click Add Staff.
3. Enter full name, username, email, and password.
4. Select role.
5. Select branch if the role is branch-level.
6. Set shift days and shift time window if needed.
7. Set max discount percentage if the user can discount sales.
8. Select permissions.
9. Save.

How to update staff:

1. Open Users.
2. Click edit on the staff row.
3. Update name, role, branch, permissions, or shift rules.
4. Save.

How to delete staff:

1. Open Users.
2. Click the delete action.
3. Confirm permanent deletion.

How delete works:

- deleting staff removes the staff login account and staff profile
- historical sales, orders, audit logs, and reports remain linked to past activity
- the system blocks deleting your own admin account
- the system blocks deleting the last active admin

How permissions work:

- role gives default access
- permission checklist can allow or block specific actions
- branch-level users are still limited to their assigned branch
- activity is logged when access changes

## 9. Module 4 - Product Management

Purpose:

- manages products, categories, brands, units, variants, barcodes, prices, and tax tags

Who uses it:

- admin
- manager or inventory staff if allowed

How to add a product:

1. Open Products.
2. Click Add Product.
3. Enter product name.
4. Select category, brand, and unit.
5. Enter SKU and barcode.
6. Enter cost price and selling price.
7. Set reorder level.
8. Choose tax tag: VATable, VAT-exempt, zero-rated, non-VAT, or percentage-tax.
9. Add variants if needed.
10. Save.

How to search products:

1. Open Products.
2. Use the search field.
3. Search by product name, SKU, barcode, category, brand, or variant.

How to delete a product:

1. Open Products.
2. Select the product.
3. Click delete.
4. Confirm.

How product delete works:

- the system allows product delete only when business rules allow it
- if the product is already linked to sales, stock, purchases, or movements, deletion may be blocked or treated as inactive depending on the current data

How the system works:

- product price is used at checkout
- cost price helps calculate profit reports
- tax tag controls VAT and tax reporting
- reorder level helps low-stock alerts
- variant barcode can be scanned separately at POS

## 10. Module 5 - Inventory Management

Purpose:

- controls stock by branch, batch, expiry date, and movement type

Who uses it:

- admin
- branch manager
- inventory staff
- auditor for review

How to add stock:

1. Open Inventory.
2. Select branch.
3. Click Stock In or Adjustment.
4. Select product and variant if needed.
5. Enter quantity.
6. Enter batch number if available.
7. Enter expiry date if applicable.
8. Save.

How to remove stock:

1. Open Inventory.
2. Select product batch.
3. Choose Stock Out, Damaged, Expired, or Adjustment Minus.
4. Enter quantity and reason.
5. Save.

How to post stock count:

1. Open Inventory.
2. Start stock count.
3. Enter counted quantity for each item.
4. Review variance.
5. Post count.

How the system works:

- stock is branch-specific
- each batch can have its own expiry date
- every stock change creates a movement record
- stock count posts variance automatically
- low-stock alerts compare current stock with reorder level
- expiry watch highlights products near expiry

## 11. Module 6 - Stock Transfer

Purpose:

- moves stock from one branch to another with approval, dispatch, receiving, and variance tracking

Who uses it:

- admin
- branch manager
- inventory staff
- auditor for review

How to request transfer:

1. Open Transfers.
2. Click New Transfer.
3. Select source branch.
4. Select destination branch.
5. Add products and requested quantities.
6. Save request.

How to approve:

1. Source branch manager or admin opens the request.
2. Review requested items.
3. Approve if stock should be moved.

How to dispatch:

1. After approval, click Dispatch.
2. The system selects stock batches using earliest expiry first.
3. Stock decreases from the source branch.
4. Dispatch details are saved.

How to receive:

1. Destination branch opens the transfer.
2. Enter received quantity.
3. Save receiving.
4. The system adds stock to the destination branch.
5. Any shortage or overage is recorded as variance.

How the system works:

- transfer has a clear status flow: request, approve, dispatch, receive
- source stock decreases at dispatch
- destination stock increases at receiving
- variance shows the difference between dispatched and received quantity

## 12. Module 7 - POS Sales And Checkout

Purpose:

- handles fast checkout, barcode scanning, discounts, payments, invoices, receipts, and stock reduction

Who uses it:

- cashier
- branch manager
- admin

How to sell:

1. Open POS.
2. Confirm branch.
3. Select customer or leave as walk-in.
4. Scan barcode or search product.
5. Add product to cart.
6. Adjust quantity if needed.
7. Apply discount if permitted.
8. Select payment method.
9. Add split payments if needed.
10. Click Checkout.
11. Print or save the receipt.

How barcode scanning works:

- USB barcode scanners act like keyboard input
- scan focuses into the barcode field
- matching product is added to cart
- repeated scan increases quantity

How discounts work:

- user must have discount permission
- discount must be within the user's allowed percentage
- discount amount is saved with the sale
- discount events appear in reports and audit review

How payments work:

- one sale can have one payment or split payments
- cash can produce change
- non-cash methods can require reference numbers
- payment details are saved with the invoice

How stock reduction works:

- after checkout, stock decreases immediately
- batches with earliest expiry are used first
- batch allocation is saved for traceability

How offline sales work:

1. Build the cart.
2. If internet is down, save offline.
3. Later, when online, click Sync Now.
4. The system submits the queued sale and reduces stock during sync.

## 13. Module 8 - Philippines Invoice And BIR Compliance

Purpose:

- manages invoice document types, branch/machine invoice numbering, reprints, void controls, and X/Z readings

Who uses it:

- admin
- branch manager
- auditor

How to set machine details:

1. Open BIR.
2. Review machine record for each branch.
3. Enter machine serial number, MIN, permit number, accreditation number, software version, and permit dates.
4. Save.

How to set invoice series:

1. Open BIR.
2. Review invoice series.
3. Set document type, prefix, current number, digit padding, start number, and end number.
4. Save.

How invoices work:

- checkout assigns invoice number automatically
- numbering follows branch and machine setup
- document type can be Sales Invoice, Cash Invoice, Charge/Credit Invoice, Service Invoice, or Billing Invoice

How reprint works:

1. Open BIR invoice list or POS recent invoice.
2. Choose reprint.
3. Enter reason if required.
4. Print copy.

How void works:

1. Find the invoice.
2. Choose void.
3. Enter reason.
4. Confirm.

Void rules:

- void reverses stock when allowed
- void is blocked after final Z-reading for the same branch/date/machine
- void action is recorded in audit logs

How readings work:

- X-reading is a temporary daily sales reading
- Z-reading is final end-of-day reading
- after Z-reading, the business day is treated as closed for protected actions

## 14. Module 9 - Tax Management

Purpose:

- controls VAT, non-VAT, percentage tax, zero-rated, exempt sales, and tax reports

Who uses it:

- admin
- manager for review if allowed
- auditor

How to configure tax profile:

1. Open Tax.
2. Review branch tax setup.
3. Assign tax profile to each branch.
4. Set VAT rate or percentage tax rate.
5. Save.

How to manage tax codes:

1. Open Tax.
2. Add or edit tax code.
3. Choose VATable, VAT-exempt, zero-rated, non-VAT, or percentage-tax.
4. Save.

How tax works at checkout:

- product tax tag decides how tax is calculated
- branch setting decides tax-inclusive or tax-exclusive pricing
- completed sales are grouped into VATable, VAT-exempt, zero-rated, non-VAT, and percentage-tax reports

## 15. Module 10 - Senior Citizen And PWD Discounts

Purpose:

- applies Senior Citizen and PWD discount rules with ID capture and separate reporting

Who uses it:

- cashier at checkout
- admin for setup
- manager and auditor for review

How to set branch rules:

1. Open Senior/PWD.
2. Select branch.
3. Set 20 percent discount rate.
4. Set VAT exemption rule.
5. Set 5 percent basic necessities or prime commodities rule if applicable.
6. Set ID and booklet capture requirements.
7. Save.

How to tag eligible products:

1. Open Senior/PWD.
2. Search product.
3. Choose eligibility type.
4. Save.

How to apply during sale:

1. Open POS.
2. Add eligible products.
3. Select Senior Citizen or PWD in checkout panel.
4. Enter beneficiary name.
5. Enter ID type and ID number.
6. Enter booklet/reference if required.
7. Checkout.

How the system works:

- discount amount is saved on the sale
- VAT exemption is tracked where applicable
- Senior/PWD claim is saved for reporting
- separate report shows beneficiary, ID details, invoice, discount, and branch

## 16. Module 11 - Payments

Purpose:

- manages payment methods, split payments, references, fees, settlement status, and payment reports

Who uses it:

- admin for setup
- cashier at checkout
- manager and auditor for review

How to enable payment method:

1. Open Payments.
2. Review payment method list.
3. Enable or disable method per branch.
4. Set whether reference is required.
5. Set whether overpayment/change is allowed.
6. Save.

Supported payment methods:

- Cash
- Credit/debit card
- GCash
- Maya
- Bank transfer
- Store credit
- COD if delivery or credit sale is used

How split payment works:

1. In POS, add payment row.
2. Select method.
3. Enter amount.
4. Add another payment row.
5. Continue until total is fully paid.
6. Checkout.

How the system works:

- payment rows are saved per invoice
- cash can calculate change
- non-cash methods can require reference numbers
- payment reports group collections by branch, cashier, and method

## 17. Module 12 - Cash Register And Shift Management

Purpose:

- controls opening cash, cash in/out, shift closing, short/over tracking, and end-of-day cash reports

Who uses it:

- cashier
- branch manager
- admin
- auditor for review

How to open shift:

1. Open Shifts.
2. Select branch and register.
3. Enter opening cash.
4. Click Open Shift.

How to cash in:

1. Open Shifts.
2. Click Cash In.
3. Enter amount and reason.
4. Save.

How to cash out:

1. Open Shifts.
2. Click Cash Out.
3. Enter amount and reason.
4. Save.

How to close shift:

1. Open Shifts.
2. Click Close Shift.
3. Enter counted cash.
4. Review expected cash.
5. Review short or over amount.
6. Confirm close.

Why shifts are important:

- they separate each cashier's responsibility
- they protect cash drawer accountability
- they show whether counted cash matches expected cash
- they make end-of-day sales and cash review easier

How the system works:

- completed POS sales attach to the open shift
- cash payments increase expected cash
- cash in/out changes drawer balance
- closing calculates short or over automatically

## 18. Module 13 - Returns And Exchanges

Purpose:

- handles returns, refunds, exchanges, void transactions, credit memos, and return reasons

Who uses it:

- cashier if allowed
- branch manager
- admin
- auditor for review

How to process return:

1. Open Returns.
2. Search invoice.
3. Select item to return.
4. Enter quantity.
5. Choose reason.
6. Choose item condition: sellable, damaged, expired, or other.
7. Choose refund method or credit memo.
8. Save.

How exchange works:

1. Return original item.
2. Issue exchange credit or credit memo.
3. Sell replacement item through POS.
4. Apply credit where allowed.

How void works:

1. Find invoice.
2. Click Void.
3. Enter reason.
4. Confirm.

How the system works:

- sellable returned stock is restored to original batch trace where possible
- damaged or expired returns are not restored as sellable stock
- refunds are tracked by method
- credit memo can be used for future customer credit
- voids are protected by invoice reading rules

## 19. Module 14 - Purchase Management

Purpose:

- manages purchase orders, receiving, supplier invoices, purchase returns, and cost tracking

Who uses it:

- admin
- manager
- inventory staff
- auditor for review

How to create purchase order:

1. Open Purchases.
2. Click New Purchase Order.
3. Select supplier.
4. Select branch.
5. Add products, quantities, and costs.
6. Save as draft.
7. Submit for approval.

How to approve:

1. Open purchase order.
2. Review products, quantities, and cost.
3. Approve.

How to receive:

1. Open approved purchase order.
2. Click Receive.
3. Enter received quantities.
4. Enter batch numbers and expiry dates.
5. Confirm receiving.

How supplier invoice works:

- received goods create supplier payable record
- invoice balance tracks pending, partial, paid, or voided status

How purchase return works:

1. Open Purchases.
2. Select received batch.
3. Click Purchase Return.
4. Enter returned quantity and reason.
5. Save.

How the system works:

- receiving increases branch stock
- received cost updates cost history
- supplier payable is created or updated
- purchase return reduces received batch stock

## 20. Module 15 - Supplier Management

Purpose:

- manages supplier profiles, payables, supplier payments, balances, and purchase history

Who uses it:

- admin
- manager
- purchasing staff
- auditor for review

How to add supplier:

1. Open Suppliers.
2. Click Add Supplier.
3. Enter supplier name.
4. Enter contact person, phone, email, address, TIN, terms, credit limit, and default payment method.
5. Set status.
6. Save.

How to view payables:

1. Open Suppliers.
2. Review payable summary.
3. Check overdue invoices.
4. Filter by supplier or branch.

How to post supplier payment:

1. Open Suppliers.
2. Select invoice.
3. Click Pay.
4. Enter amount, date, method, and reference.
5. Save.

How to void supplier payment:

1. Open supplier payment ledger.
2. Select posted payment.
3. Click Void.
4. Enter reason.
5. Confirm.

How the system works:

- supplier payment reduces invoice balance
- voiding payment restores the unpaid balance
- supplier purchase history comes from received purchases

## 21. Module 16 - Customer Management

Purpose:

- manages customer profiles, purchase history, credit sales, store credit, loyalty points, and receivables

Who uses it:

- admin
- manager
- cashier
- auditor for review

How to add customer:

1. Open Customers.
2. Click Add Customer.
3. Enter customer name, type, phone, email, address, TIN, branch, credit limit, and status.
4. Save.

How to use customer in POS:

1. Open POS.
2. Select customer before checkout.
3. Complete sale.

How purchase history works:

- completed sales linked to a customer appear in purchase history
- customer report shows total purchases and balance

How receivables work:

1. Use COD or customer credit payment method where allowed.
2. Sale creates customer receivable.
3. Later, open Customers.
4. Post customer payment.
5. Balance decreases.

How store credit works:

- credit memo or manual store credit increases customer credit
- store credit payment can apply credit to sales

How loyalty works:

- completed purchases can earn loyalty points
- admin can adjust points when permitted
- ledger records every loyalty movement

## 22. Module 17 - Expenses

Purpose:

- tracks branch expenses such as rent, utilities, salaries, supplies, repairs, transport, marketing, and other costs

Who uses it:

- admin
- branch manager
- auditor for review

How to add expense:

1. Open Expenses.
2. Click New Expense.
3. Select branch.
4. Select category.
5. Enter date, payee, amount, tax amount if any, payment method, and notes.
6. Save as draft or submit.

How approval works:

1. Submitted expense waits for approval.
2. Manager or admin reviews it.
3. Approve or reject.
4. If paid, mark as paid.

How void works:

1. Open expense.
2. Click Void.
3. Enter reason.
4. Confirm.

How the system works:

- expenses reduce profit reports
- paid expenses affect cash ledger where applicable
- category charts help review cost areas
- approval trail is recorded

## 23. Module 18 - Accounting

Purpose:

- gives financial views for sales journal, cash ledger, receivables, payables, profit/loss, VAT payable, trial balance, and manual journals

Who uses it:

- admin
- auditor
- manager for allowed branch scope

How to view accounting dashboard:

1. Open Accounting.
2. Select date range and branch.
3. Review revenue, cost, gross profit, expenses, net profit, cash, receivables, payables, and VAT.

How sales journal works:

- completed invoices become sales journal rows
- rows include invoice number, branch, revenue, VAT, total, and cost

How cash ledger works:

- cash-equivalent sale payments, customer payments, supplier payments, and paid expenses appear in the ledger

How receivables work:

- customer credit sales increase receivables
- customer payments reduce receivables

How payables work:

- supplier invoices increase payables
- supplier payments reduce payables

How manual journal works:

1. Open Accounting.
2. Click Manual Journal.
3. Enter date, branch, reference, memo, debit lines, and credit lines.
4. Make sure total debits equal total credits.
5. Post journal.

How the system works:

- accounting reports summarize business activity
- manual journals allow controlled adjustments
- voided journals are excluded from active totals where applicable

## 24. Module 19 - Reports

Purpose:

- gives detailed operational and financial reports for sales, stock, tax, discounts, readings, and profit

Who uses it:

- admin
- branch manager
- auditor

How to use reports:

1. Open Reports.
2. Select report type.
3. Select date range.
4. Select branch if allowed.
5. Use search if needed.
6. Review chart and table.
7. Click Export CSV to download the active report.

Report types:

- daily sales
- branch sales
- cashier sales
- invoice sales detail
- top products
- payment mix
- inventory report
- stock movement
- VAT sales
- Senior/PWD discount
- Z-reading
- profit

How the system works:

- daily reports show only days with records
- branch-level users see only assigned branch data
- reports use completed business records
- CSV export downloads the current filtered view

## 25. Module 20 - Audit Logs

Purpose:

- records important activity for security, review, and accountability

Who uses it:

- admin
- auditor
- branch manager for branch-scoped activity

How to use audit logs:

1. Open Audit Logs.
2. Select date range.
3. Select branch, actor, category, or severity if needed.
4. Search by text.
5. Review overview cards.
6. Review daily audit chart and category chart.
7. Open Activity, Access, Controls, Discounts, or Inventory sections.
8. Export CSV if needed.

What is tracked:

- login and logout history
- voids
- deleted records
- price changes
- discounts
- stock adjustments
- damaged and expired stock movements
- user and access changes
- high-risk events

How the system works:

- actions are classified by category and severity
- admin and auditor can review all branches
- managers can review assigned branch activity
- audit history supports investigation and accountability

## 26. PWA Install Support

Purpose:

- lets users install the system like an app on desktop, tablet, or mobile

How to test locally:

1. Run the app.
2. Open the app in Chrome or Edge.
3. Open `/manifest.webmanifest` and confirm JSON appears.
4. Refresh the app.
5. Use the browser install icon if available.

How to install on desktop:

1. Open the deployed app URL in Chrome or Edge.
2. Login once.
3. Click the install icon in the address bar.
4. Confirm install.
5. Open the app from desktop/start menu.

How to install on mobile:

1. Open the deployed app URL.
2. Use browser menu.
3. Choose Add to Home Screen.
4. Open from home-screen icon.

Important:

- production install needs HTTPS
- localhost is accepted for testing
- local network IP addresses usually need HTTPS to be installable
- app shell can load after first successful visit
- live sales, stock, staff, and reporting actions still need network access unless POS offline queue is used

## 27. Complete Checkout Flow Example

1. Cashier opens shift with opening cash.
2. Cashier opens POS.
3. Cashier scans product barcode.
4. Product is added to cart.
5. Cashier selects customer if known.
6. Cashier applies allowed discount if needed.
7. Cashier selects payment method.
8. Cashier completes checkout.
9. System saves invoice.
10. System saves items and payments.
11. System calculates tax.
12. System allocates stock from earliest expiry batches.
13. System decreases branch stock.
14. System updates cashier and branch sales reports.
15. System updates payment reports.
16. System updates cash drawer expected amount if payment is cash.
17. System updates customer purchase history if customer is selected.
18. System updates accounting summaries.
19. System records important activity for audit.
20. Cashier prints or saves receipt.

## 28. Complete Purchasing And Receiving Flow Example

1. Admin or manager creates supplier.
2. User creates purchase order.
3. Purchase order is submitted.
4. Approver reviews and approves.
5. Goods arrive at branch.
6. User posts receiving.
7. User enters batch number and expiry date.
8. System increases branch stock.
9. System saves cost history.
10. System creates or updates supplier invoice.
11. Supplier payable appears in reports.
12. Supplier payment can be posted later.

## 29. Complete Stock Transfer Flow Example

1. Destination branch requests stock.
2. Source branch approves.
3. Source branch dispatches.
4. System selects earliest expiry batches.
5. Source stock decreases.
6. Destination branch receives.
7. Destination stock increases.
8. Variance is recorded if received quantity differs.
9. Transfer appears in stock movement and reports.

## 30. Complete Return Flow Example

1. User finds original invoice.
2. User selects item and return quantity.
3. User chooses reason and condition.
4. User selects refund, exchange, or credit memo.
5. System saves return record.
6. If item is sellable, stock is restored.
7. If item is damaged or expired, stock is not restored as sellable.
8. Refund/payment impact is tracked.
9. Reports and audit records update.

## 31. End-Of-Day Flow

1. Cashier finishes sales.
2. Manager reviews POS invoices.
3. Cashier counts cash drawer.
4. Cashier closes shift.
5. System calculates expected cash.
6. System calculates short or over.
7. Manager reviews cash in/out movements.
8. Manager generates Z-reading.
9. Reports are reviewed.
10. Accounting dashboard is checked.
11. Audit logs are reviewed for voids, discounts, and high-risk activity.

## 32. Common Troubleshooting

Missing page:

- check user role and permissions
- check branch assignment
- login again after permission changes

Product not found in POS:

- check product active status
- check barcode or SKU
- check branch stock
- check variant barcode if variant is used

Cannot checkout:

- check open shift
- check stock availability
- check payment total
- check required reference number
- check discount permission

Shift says "Shift not found" when closing:

- refresh the Shifts page and try closing again
- make sure the shift is still open
- make sure you are closing the shift from the correct branch
- if the error keeps happening, rerun the latest Module 12 setup file because older installs may not return the shift ID needed for closing
- after rerunning the setup file, refresh the app and open the Shifts page again

Cannot hard delete:

- record likely has linked history
- disable the record instead

PWA install icon not showing:

- test in Chrome or Edge
- refresh once
- check `/manifest.webmanifest`
- unregister old service worker if browser cached an old version
- use HTTPS for deployed app

Reports look different between users:

- admin sees all allowed branch data
- manager sees assigned branch data
- auditor sees view-only scope
- date range and branch filters affect results

## 33. Best Practices

- create branches before staff
- assign every branch a clear branch code
- use real machine and invoice serial details before live operations
- add products with correct tax tags
- enter expiry dates for perishable stock
- require references for non-cash payments
- open cashier shifts before selling
- close shifts daily
- use Z-reading only when the business day is final
- review reports daily
- review audit logs for voids, discounts, price changes, and stock adjustments
- disable old branches and users instead of hard deleting records with history

## 34. Quick Role Checklist

Admin daily checklist:

- review Dashboard
- check low stock
- review sales and branch performance
- review reports
- review audit logs
- manage branches, users, products, taxes, and settings

Branch Manager daily checklist:

- open or monitor shifts
- review branch sales
- approve stock transfers
- receive purchases
- monitor low stock and expiry
- review returns and voids
- close day with readings and shift reports

Cashier daily checklist:

- open shift
- sell through POS
- scan products carefully
- collect correct payment
- print or save receipt
- process allowed returns only
- close shift with counted cash

Auditor checklist:

- review reports
- verify readings
- check audit logs
- inspect voids, discounts, stock adjustments, and price changes
- export evidence when needed

Inventory staff checklist:

- receive stock with batch and expiry details
- post adjustments with reasons
- count physical stock
- process transfers
- monitor damaged, expired, and low-stock items
