<template>
  <section class="page-stack">
    <section class="page-hero">
      <div>
        <p class="eyebrow">Module 14</p>
        <h2>Purchase orders, receiving, supplier invoices, purchase returns, and cost tracking.</h2>
        <p>
          Create purchase orders, approve branch requests, post goods received notes into inventory batches,
          track supplier invoice balances, and return received stock when supplier deliveries need correction.
        </p>
      </div>

      <form class="filter-panel" @submit.prevent="loadPurchases">
        <label>
          From
          <PDatePicker v-model="filters.from" date-format="yy-mm-dd" show-icon fluid />
        </label>
        <label>
          To
          <PDatePicker v-model="filters.to" date-format="yy-mm-dd" show-icon fluid />
        </label>
        <label>
          Branch
          <PSelect
            v-model="filters.branchId"
            :options="branchFilterOptions"
            option-label="name"
            option-value="id"
            placeholder="All branches"
            :disabled="isBranchLocked"
            fluid
          />
        </label>
        <label>
          Search
          <PInputText v-model.trim="filters.search" placeholder="PO, GRN, invoice, supplier" fluid />
        </label>
        <div class="dialog-actions">
          <PButton type="submit" icon="pi pi-refresh" label="Refresh" :loading="loading" />
          <PButton type="button" icon="pi pi-plus" label="New PO" :disabled="!canManagePurchases" @click="openPurchaseOrder" />
          <PButton type="button" icon="pi pi-truck" label="Receive" outlined :disabled="!canReceivePurchases" @click="openReceive" />
          <PButton type="button" icon="pi pi-address-book" label="Supplier" outlined :disabled="!canManagePurchases" @click="openSupplier" />
        </div>
      </form>
    </section>

    <PMessage v-if="error" severity="error" :closable="false" class="setup-message">
      {{ error }}
    </PMessage>

    <PMessage v-if="successMessage" severity="success" :closable="false" class="setup-message">
      {{ successMessage }}
    </PMessage>

    <section v-if="loading && !purchaseData" class="stats-grid">
      <PSkeleton v-for="item in 6" :key="item" height="8rem" border-radius="8px" />
    </section>

    <template v-else-if="purchaseData">
      <section class="stats-grid">
        <MetricCard label="Open POs" :value="formatNumber(purchaseData.summary.open_orders)" :caption="periodLabel" icon="pi pi-file-edit" />
        <MetricCard label="Received value" :value="formatCurrency(purchaseData.summary.received_value)" icon="pi pi-truck" tone="blue" />
        <MetricCard label="Payables" :value="formatCurrency(purchaseData.summary.payable_amount)" icon="pi pi-wallet" tone="gold" />
        <MetricCard label="Overdue bills" :value="formatNumber(purchaseData.summary.overdue_invoices)" icon="pi pi-clock" tone="red" />
        <MetricCard label="Purchase returns" :value="formatCurrency(purchaseData.summary.purchase_return_amount)" icon="pi pi-undo" tone="purple" />
        <MetricCard label="Suppliers" :value="formatNumber(purchaseData.summary.supplier_count)" icon="pi pi-address-book" tone="green" />
      </section>

      <section class="analytics-grid">
        <BarChart
          title="Daily received value"
          eyebrow="Receiving trend"
          :rows="purchaseData.daily_receipts"
          key-field="business_date"
          label-field="label"
          value-field="received_value"
          caption="Posted GRNs"
        />
        <BarChart
          title="Purchases by branch"
          eyebrow="Branch comparison"
          :rows="purchaseData.branch_summary"
          key-field="branch_id"
          label-field="branch_name"
          value-field="received_value"
          caption="Received value"
        />
      </section>

      <section class="panel">
        <div class="table-toolbar product-toolbar">
          <div>
            <p class="eyebrow">Purchase orders</p>
            <h2>Requests, approvals, and receiving status</h2>
          </div>
          <span class="search-field">
            <i class="pi pi-search" />
            <PInputText v-model.trim="orderSearch" placeholder="Search PO, supplier, branch" />
          </span>
        </div>

        <PDataTable
          :value="filteredOrders"
          data-key="id"
          responsive-layout="stack"
          breakpoint="960px"
          size="small"
          striped-rows
          paginator
          :rows="10"
        >
          <PColumn field="po_number" header="PO">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.po_number }}</strong>
                <small>{{ formatDate(data.order_date) }}{{ data.expected_date ? ` - Due ${formatDate(data.expected_date)}` : '' }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="supplier_name" header="Supplier">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.supplier_name }}</strong>
                <small>{{ data.supplier_code }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="branch_name" header="Branch">
            <template #body="{ data }">{{ data.branch_code }} - {{ data.branch_name }}</template>
          </PColumn>
          <PColumn field="status" header="Status">
            <template #body="{ data }">
              <PTag :value="statusLabel(data.status)" :severity="statusSeverity(data.status)" />
              <small class="muted-block">{{ formatNumber(data.received_quantity) }} / {{ formatNumber(data.ordered_quantity) }} received</small>
            </template>
          </PColumn>
          <PColumn field="total" header="Total">
            <template #body="{ data }">
              {{ formatCurrency(data.total) }}
              <small class="muted-block">{{ formatNumber(data.item_count) }} item(s)</small>
            </template>
          </PColumn>
          <PColumn header="Actions">
            <template #body="{ data }">
              <div class="table-actions">
                <PButton
                  icon="pi pi-pencil"
                  text
                  rounded
                  aria-label="Edit PO"
                  :disabled="!canManagePurchases || !canEditOrder(data)"
                  @click="openPurchaseOrder(data)"
                />
                <PButton
                  icon="pi pi-send"
                  text
                  rounded
                  aria-label="Submit PO"
                  :disabled="!canManagePurchases || data.status !== 'draft'"
                  @click="changeOrderStatus(data, 'submitted')"
                />
                <PButton
                  icon="pi pi-check"
                  text
                  rounded
                  aria-label="Approve PO"
                  :disabled="!canApprovePurchases || !['draft', 'submitted'].includes(data.status)"
                  @click="changeOrderStatus(data, 'approved')"
                />
                <PButton
                  icon="pi pi-truck"
                  text
                  rounded
                  aria-label="Receive PO"
                  :disabled="!canReceivePurchases || !canReceiveOrder(data)"
                  @click="openReceive(data)"
                />
                <PButton
                  icon="pi pi-times"
                  text
                  rounded
                  severity="danger"
                  aria-label="Cancel PO"
                  :disabled="!canManagePurchases || ['received', 'closed', 'cancelled'].includes(data.status)"
                  @click="changeOrderStatus(data, 'cancelled')"
                />
              </div>
            </template>
          </PColumn>
        </PDataTable>
      </section>

      <section class="analytics-grid">
        <section class="panel">
          <div class="table-toolbar product-toolbar">
            <div>
              <p class="eyebrow">Receiving</p>
              <h2>Goods received notes</h2>
            </div>
            <span class="search-field">
              <i class="pi pi-search" />
              <PInputText v-model.trim="receiptSearch" placeholder="Search GRN, supplier, invoice" />
            </span>
          </div>

          <PDataTable
            :value="filteredReceipts"
            data-key="id"
            responsive-layout="stack"
            breakpoint="860px"
            size="small"
            striped-rows
            paginator
            :rows="8"
          >
            <PColumn field="receipt_number" header="GRN">
              <template #body="{ data }">
                <div class="branch-cell">
                  <strong>{{ data.receipt_number }}</strong>
                  <small>{{ formatDate(data.receipt_date) }} - {{ data.po_number || 'Direct receiving' }}</small>
                </div>
              </template>
            </PColumn>
            <PColumn field="supplier_name" header="Supplier" />
            <PColumn field="total_cost" header="Cost">
              <template #body="{ data }">
                {{ formatCurrency(data.total_cost) }}
                <small class="muted-block">{{ formatNumber(data.received_quantity) }} units</small>
              </template>
            </PColumn>
            <PColumn header="Actions">
              <template #body="{ data }">
                <div class="table-actions">
                  <PButton
                    icon="pi pi-undo"
                    text
                    rounded
                    aria-label="Return received stock"
                    :disabled="!canManagePurchases || !receiptHasReturnableItems(data)"
                    @click="openPurchaseReturn(data)"
                  />
                </div>
              </template>
            </PColumn>
          </PDataTable>
        </section>

        <section class="panel">
          <div class="table-toolbar product-toolbar">
            <div>
              <p class="eyebrow">Supplier invoices</p>
              <h2>Payables and settlement</h2>
            </div>
            <span class="search-field">
              <i class="pi pi-search" />
              <PInputText v-model.trim="invoiceSearch" placeholder="Search invoice, supplier, branch" />
            </span>
          </div>

          <PDataTable
            :value="filteredInvoices"
            data-key="id"
            responsive-layout="stack"
            breakpoint="860px"
            size="small"
            striped-rows
            paginator
            :rows="8"
          >
            <PColumn field="invoice_number" header="Invoice">
              <template #body="{ data }">
                <div class="branch-cell">
                  <strong>{{ data.invoice_number }}</strong>
                  <small>{{ data.receipt_number }} - Due {{ data.due_date ? formatDate(data.due_date) : '-' }}</small>
                </div>
              </template>
            </PColumn>
            <PColumn field="supplier_name" header="Supplier" />
            <PColumn field="balance_amount" header="Balance">
              <template #body="{ data }">
                {{ formatCurrency(data.balance_amount) }}
                <small class="muted-block">Paid {{ formatCurrency(data.paid_amount) }}</small>
              </template>
            </PColumn>
            <PColumn field="status" header="Status">
              <template #body="{ data }">
                <PTag :value="invoiceStatusLabel(data.status)" :severity="invoiceStatusSeverity(data.status)" />
              </template>
            </PColumn>
            <PColumn header="Actions">
              <template #body="{ data }">
                <PButton
                  icon="pi pi-wallet"
                  text
                  rounded
                  aria-label="Update invoice payment"
                  :disabled="!canManagePurchases"
                  @click="openInvoiceDialog(data)"
                />
              </template>
            </PColumn>
          </PDataTable>
        </section>
      </section>

      <section class="analytics-grid">
        <section class="panel">
          <div class="table-toolbar product-toolbar">
            <div>
              <p class="eyebrow">Suppliers</p>
              <h2>Quick supplier list</h2>
            </div>
            <span class="search-field">
              <i class="pi pi-search" />
              <PInputText v-model.trim="supplierSearch" placeholder="Search supplier" />
            </span>
          </div>

          <PDataTable
            :value="filteredSuppliers"
            data-key="id"
            responsive-layout="stack"
            breakpoint="760px"
            size="small"
            striped-rows
            paginator
            :rows="8"
          >
            <PColumn field="name" header="Supplier">
              <template #body="{ data }">
                <div class="branch-cell">
                  <strong>{{ data.name }}</strong>
                  <small>{{ data.supplier_code }} - {{ data.contact_person || 'No contact' }}</small>
                </div>
              </template>
            </PColumn>
            <PColumn field="pending_amount" header="Payable">
              <template #body="{ data }">{{ formatCurrency(data.pending_amount) }}</template>
            </PColumn>
            <PColumn field="open_orders" header="Open POs" />
            <PColumn header="Actions">
              <template #body="{ data }">
                <PButton
                  icon="pi pi-pencil"
                  text
                  rounded
                  aria-label="Edit supplier"
                  :disabled="!canManagePurchases"
                  @click="openSupplier(data)"
                />
              </template>
            </PColumn>
          </PDataTable>
        </section>

        <section class="panel">
          <div class="panel__header">
            <div>
              <p class="eyebrow">Cost tracking</p>
              <h2>Latest received costs</h2>
            </div>
          </div>

          <PDataTable
            :value="purchaseData.cost_history"
            data-key="id"
            responsive-layout="stack"
            breakpoint="760px"
            size="small"
            striped-rows
            paginator
            :rows="8"
          >
            <PColumn field="product_name" header="Product">
              <template #body="{ data }">
                <div class="branch-cell">
                  <strong>{{ data.product_name }}</strong>
                  <small>{{ data.variant_name || data.sku }} - {{ data.supplier_name || 'No supplier' }}</small>
                </div>
              </template>
            </PColumn>
            <PColumn field="branch_name" header="Branch" />
            <PColumn field="unit_cost" header="Unit cost">
              <template #body="{ data }">{{ formatCurrency(data.unit_cost) }}</template>
            </PColumn>
            <PColumn field="quantity" header="Qty">
              <template #body="{ data }">{{ formatNumber(data.quantity) }}</template>
            </PColumn>
          </PDataTable>
        </section>
      </section>

      <section class="panel">
        <div class="table-toolbar product-toolbar">
          <div>
            <p class="eyebrow">Purchase returns</p>
            <h2>Returned supplier deliveries</h2>
          </div>
          <span class="search-field">
            <i class="pi pi-search" />
            <PInputText v-model.trim="returnSearch" placeholder="Search return, supplier, GRN" />
          </span>
        </div>

        <PDataTable
          :value="filteredReturns"
          data-key="id"
          responsive-layout="stack"
          breakpoint="900px"
          size="small"
          striped-rows
          paginator
          :rows="8"
        >
          <PColumn field="return_number" header="Return">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.return_number }}</strong>
                <small>{{ formatDateTime(data.created_at) }} - {{ data.receipt_number }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="supplier_name" header="Supplier" />
          <PColumn field="branch_name" header="Branch" />
          <PColumn field="reason" header="Reason" />
          <PColumn field="total_amount" header="Amount">
            <template #body="{ data }">{{ formatCurrency(data.total_amount) }}</template>
          </PColumn>
        </PDataTable>
      </section>
    </template>

    <PDialog
      v-model:visible="supplierDialogVisible"
      modal
      :header="editingSupplier ? 'Edit supplier' : 'Add supplier'"
      class="branch-dialog"
      :style="{ width: 'min(860px, 96vw)' }"
    >
      <form class="dialog-form" @submit.prevent="submitSupplier">
        <PMessage v-if="formError" severity="error" :closable="false" class="dialog-message">
          {{ formError }}
        </PMessage>

        <div class="form-grid">
          <label>
            Supplier name
            <PInputText v-model.trim="supplierForm.name" fluid />
          </label>
          <label>
            Supplier code
            <PInputText v-model.trim="supplierForm.supplier_code" placeholder="Auto if blank" fluid />
          </label>
          <label>
            Contact person
            <PInputText v-model.trim="supplierForm.contact_person" fluid />
          </label>
          <label>
            Phone
            <PInputText v-model.trim="supplierForm.phone" fluid />
          </label>
          <label>
            Email
            <PInputText v-model.trim="supplierForm.email" fluid />
          </label>
          <label>
            TIN
            <PInputText v-model.trim="supplierForm.tin" fluid />
          </label>
          <label>
            Payment terms
            <PInputNumber v-model="supplierForm.payment_terms_days" suffix=" days" :min="0" :max="365" :use-grouping="false" fluid />
          </label>
          <label>
            Credit limit
            <PInputNumber v-model="supplierForm.credit_limit" mode="currency" :currency="currencyCode" locale="en-PH" :min="0" fluid />
          </label>
        </div>

        <label>
          Address
          <PTextarea v-model.trim="supplierForm.address" rows="2" auto-resize fluid />
        </label>
        <label>
          Notes
          <PTextarea v-model.trim="supplierForm.notes" rows="2" auto-resize fluid />
        </label>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="supplierDialogVisible = false" />
          <PButton type="submit" icon="pi pi-save" label="Save supplier" :loading="saving" />
        </div>
      </form>
    </PDialog>

    <PDialog
      v-model:visible="orderDialogVisible"
      modal
      :header="editingOrder ? 'Edit purchase order' : 'New purchase order'"
      class="branch-dialog"
      :style="{ width: 'min(1040px, 96vw)' }"
    >
      <form class="dialog-form" @submit.prevent="submitPurchaseOrder">
        <PMessage v-if="formError" severity="error" :closable="false" class="dialog-message">
          {{ formError }}
        </PMessage>

        <div class="form-grid">
          <label>
            Branch
            <PSelect
              v-model="orderForm.branch_id"
              :options="branchOptions"
              option-label="name"
              option-value="id"
              placeholder="Select branch"
              :disabled="isBranchLocked"
              fluid
            />
          </label>
          <label>
            Supplier
            <PSelect v-model="orderForm.supplier_id" :options="supplierOptions" option-label="label" option-value="value" placeholder="Select supplier" fluid />
          </label>
          <label>
            Order date
            <PDatePicker v-model="orderForm.order_date" date-format="yy-mm-dd" show-icon fluid />
          </label>
          <label>
            Expected date
            <PDatePicker v-model="orderForm.expected_date" date-format="yy-mm-dd" show-icon fluid />
          </label>
        </div>

        <section class="mini-section">
          <div class="mini-section__header">
            <div>
              <h3>Order items</h3>
              <small class="muted-block">{{ formatCurrency(orderTotal) }} total including tax</small>
            </div>
            <PButton type="button" icon="pi pi-plus" label="Add item" outlined @click="addOrderItem" />
          </div>

          <div class="count-list">
            <article v-for="(item, index) in orderForm.items" :key="item.local_key" class="count-row">
              <div class="form-grid">
                <label>
                  Product
                  <PSelect
                    v-model="item.product_id"
                    :options="productOptions"
                    option-label="label"
                    option-value="value"
                    placeholder="Select product"
                    fluid
                    @change="onOrderProductChange(item)"
                  />
                </label>
                <label>
                  Variant
                  <PSelect
                    v-model="item.product_variant_id"
                    :options="variantOptionsForProduct(item.product_id)"
                    option-label="label"
                    option-value="value"
                    placeholder="No variant"
                    show-clear
                    fluid
                    @change="onOrderVariantChange(item)"
                  />
                </label>
                <label>
                  Quantity
                  <PInputNumber v-model="item.quantity_ordered" :min="1" :use-grouping="false" fluid />
                </label>
                <label>
                  Unit cost
                  <PInputNumber v-model="item.unit_cost" mode="currency" :currency="currencyCode" locale="en-PH" :min="0" fluid />
                </label>
                <label>
                  Tax rate
                  <PInputNumber v-model="item.tax_rate" suffix="%" :min="0" :max="100" fluid />
                </label>
              </div>
              <div class="count-row__footer">
                <span>Line total {{ formatCurrency(purchaseLineTotal(item)) }}</span>
                <PButton type="button" icon="pi pi-trash" text rounded severity="danger" aria-label="Remove item" @click="removeOrderItem(index)" />
              </div>
            </article>
          </div>
        </section>

        <label>
          Notes
          <PTextarea v-model.trim="orderForm.notes" rows="3" auto-resize fluid />
        </label>

        <div class="checkout-totals">
          <span>Subtotal <strong>{{ formatCurrency(orderSubtotal) }}</strong></span>
          <span>Tax <strong>{{ formatCurrency(orderTaxTotal) }}</strong></span>
          <span class="checkout-totals__grand">Total <strong>{{ formatCurrency(orderTotal) }}</strong></span>
        </div>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="orderDialogVisible = false" />
          <PButton type="submit" icon="pi pi-save" label="Save PO" :loading="saving" />
        </div>
      </form>
    </PDialog>

    <PDialog
      v-model:visible="receiveDialogVisible"
      modal
      :header="receiveForm.purchase_order_id ? 'Receive purchase order' : 'Direct receiving'"
      class="branch-dialog"
      :style="{ width: 'min(1040px, 96vw)' }"
    >
      <form class="dialog-form" @submit.prevent="submitReceive">
        <PMessage v-if="formError" severity="error" :closable="false" class="dialog-message">
          {{ formError }}
        </PMessage>

        <div v-if="selectedReceiveOrder" class="copy-panel">
          <div>
            <h2>{{ selectedReceiveOrder.po_number }}</h2>
            <p>{{ selectedReceiveOrder.supplier_name }} - {{ selectedReceiveOrder.branch_name }}</p>
          </div>
          <PTag :value="statusLabel(selectedReceiveOrder.status)" :severity="statusSeverity(selectedReceiveOrder.status)" />
        </div>

        <div class="form-grid">
          <label>
            Branch
            <PSelect
              v-model="receiveForm.branch_id"
              :options="branchOptions"
              option-label="name"
              option-value="id"
              placeholder="Select branch"
              :disabled="Boolean(receiveForm.purchase_order_id) || isBranchLocked"
              fluid
            />
          </label>
          <label>
            Supplier
            <PSelect
              v-model="receiveForm.supplier_id"
              :options="supplierOptions"
              option-label="label"
              option-value="value"
              placeholder="Select supplier"
              :disabled="Boolean(receiveForm.purchase_order_id)"
              fluid
            />
          </label>
          <label>
            Receipt date
            <PDatePicker v-model="receiveForm.receipt_date" date-format="yy-mm-dd" show-icon fluid />
          </label>
          <label>
            Supplier invoice
            <PInputText v-model.trim="receiveForm.supplier_invoice_number" placeholder="Supplier invoice number" fluid />
          </label>
          <label>
            Invoice date
            <PDatePicker v-model="receiveForm.invoice_date" date-format="yy-mm-dd" show-icon fluid />
          </label>
          <label>
            Due date
            <PDatePicker v-model="receiveForm.due_date" date-format="yy-mm-dd" show-icon fluid />
          </label>
        </div>

        <section class="mini-section">
          <div class="mini-section__header">
            <div>
              <h3>Received items</h3>
              <small class="muted-block">{{ formatCurrency(receiveTotal) }} will be posted to inventory and payables</small>
            </div>
            <PButton type="button" icon="pi pi-plus" label="Add item" outlined :disabled="Boolean(receiveForm.purchase_order_id)" @click="addReceiveItem" />
          </div>

          <div class="count-list">
            <article v-for="(item, index) in receiveForm.items" :key="item.local_key" class="count-row">
              <div class="form-grid">
                <label>
                  Product
                  <PSelect
                    v-model="item.product_id"
                    :options="productOptions"
                    option-label="label"
                    option-value="value"
                    placeholder="Select product"
                    :disabled="Boolean(item.purchase_order_item_id)"
                    fluid
                    @change="onReceiveProductChange(item)"
                  />
                </label>
                <label>
                  Variant
                  <PSelect
                    v-model="item.product_variant_id"
                    :options="variantOptionsForProduct(item.product_id)"
                    option-label="label"
                    option-value="value"
                    placeholder="No variant"
                    show-clear
                    :disabled="Boolean(item.purchase_order_item_id)"
                    fluid
                    @change="onReceiveVariantChange(item)"
                  />
                </label>
                <label>
                  Quantity
                  <PInputNumber v-model="item.quantity_received" :min="0" :max="item.remaining_quantity || null" :use-grouping="false" fluid />
                </label>
                <label>
                  Unit cost
                  <PInputNumber v-model="item.unit_cost" mode="currency" :currency="currencyCode" locale="en-PH" :min="0" fluid />
                </label>
                <label>
                  Tax rate
                  <PInputNumber v-model="item.tax_rate" suffix="%" :min="0" :max="100" fluid />
                </label>
                <label>
                  Batch number
                  <PInputText v-model.trim="item.batch_number" placeholder="Auto if blank" fluid />
                </label>
                <label>
                  Expiry date
                  <PDatePicker v-model="item.expiry_date" date-format="yy-mm-dd" show-icon fluid />
                </label>
              </div>
              <div class="count-row__footer">
                <span>
                  {{ item.remaining_quantity ? `${formatNumber(item.remaining_quantity)} remaining - ` : '' }}
                  Line total {{ formatCurrency(receiveLineTotal(item)) }}
                </span>
                <PButton
                  type="button"
                  icon="pi pi-trash"
                  text
                  rounded
                  severity="danger"
                  aria-label="Remove item"
                  :disabled="Boolean(receiveForm.purchase_order_id)"
                  @click="removeReceiveItem(index)"
                />
              </div>
            </article>
          </div>
        </section>

        <label>
          Notes
          <PTextarea v-model.trim="receiveForm.notes" rows="3" auto-resize fluid />
        </label>

        <div class="checkout-totals">
          <span>Subtotal <strong>{{ formatCurrency(receiveSubtotal) }}</strong></span>
          <span>Tax <strong>{{ formatCurrency(receiveTaxTotal) }}</strong></span>
          <span class="checkout-totals__grand">Total <strong>{{ formatCurrency(receiveTotal) }}</strong></span>
        </div>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="receiveDialogVisible = false" />
          <PButton type="submit" icon="pi pi-check" label="Post receiving" :loading="saving" />
        </div>
      </form>
    </PDialog>

    <PDialog v-model:visible="invoiceDialogVisible" modal header="Update supplier invoice" class="branch-dialog" :style="{ width: 'min(620px, 96vw)' }">
      <form class="dialog-form" @submit.prevent="submitInvoiceStatus">
        <PMessage v-if="formError" severity="error" :closable="false" class="dialog-message">
          {{ formError }}
        </PMessage>

        <div v-if="selectedInvoice" class="copy-panel">
          <div>
            <h2>{{ selectedInvoice.invoice_number }}</h2>
            <p>{{ selectedInvoice.supplier_name }} - Balance {{ formatCurrency(selectedInvoice.balance_amount) }}</p>
          </div>
          <PTag :value="invoiceStatusLabel(selectedInvoice.status)" :severity="invoiceStatusSeverity(selectedInvoice.status)" />
        </div>

        <div class="form-grid">
          <label>
            Status
            <PSelect v-model="invoiceForm.status" :options="invoiceStatusOptions" option-label="label" option-value="value" fluid />
          </label>
          <label>
            Paid amount
            <PInputNumber v-model="invoiceForm.paid_amount" mode="currency" :currency="currencyCode" locale="en-PH" :min="0" :max="selectedInvoice?.amount || null" fluid />
          </label>
        </div>

        <label>
          Notes
          <PTextarea v-model.trim="invoiceForm.notes" rows="3" auto-resize fluid />
        </label>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="invoiceDialogVisible = false" />
          <PButton type="submit" icon="pi pi-save" label="Update invoice" :loading="saving" />
        </div>
      </form>
    </PDialog>

    <PDialog v-model:visible="returnDialogVisible" modal header="Return received stock" class="branch-dialog" :style="{ width: 'min(960px, 96vw)' }">
      <form class="dialog-form" @submit.prevent="submitPurchaseReturn">
        <PMessage v-if="formError" severity="error" :closable="false" class="dialog-message">
          {{ formError }}
        </PMessage>

        <div v-if="selectedReturnReceipt" class="copy-panel">
          <div>
            <h2>{{ selectedReturnReceipt.receipt_number }}</h2>
            <p>{{ selectedReturnReceipt.supplier_name }} - {{ selectedReturnReceipt.branch_name }}</p>
          </div>
          <PTag :value="formatCurrency(returnTotal)" severity="info" />
        </div>

        <div class="form-grid">
          <label>
            Reason
            <PInputText v-model.trim="returnForm.reason" placeholder="Damaged, short, wrong item, supplier recall" fluid />
          </label>
          <label>
            Notes
            <PInputText v-model.trim="returnForm.notes" placeholder="Optional internal note" fluid />
          </label>
        </div>

        <PDataTable
          :value="returnForm.items"
          data-key="receipt_item_id"
          responsive-layout="stack"
          breakpoint="820px"
          size="small"
          striped-rows
        >
          <PColumn field="product_name" header="Item">
            <template #body="{ data }">
              <div class="branch-cell">
                <strong>{{ data.product_name }}</strong>
                <small>{{ data.variant_name || data.sku }} - Batch {{ data.batch_number || '-' }}</small>
              </div>
            </template>
          </PColumn>
          <PColumn field="available_quantity" header="Available">
            <template #body="{ data }">{{ formatNumber(data.available_quantity) }}</template>
          </PColumn>
          <PColumn field="unit_cost" header="Unit cost">
            <template #body="{ data }">{{ formatCurrency(data.unit_cost) }}</template>
          </PColumn>
          <PColumn header="Return qty">
            <template #body="{ data }">
              <PInputNumber v-model="data.quantity_returned" :min="0" :max="data.available_quantity" :use-grouping="false" fluid />
            </template>
          </PColumn>
          <PColumn header="Line">
            <template #body="{ data }">{{ formatCurrency(Number(data.quantity_returned || 0) * Number(data.unit_cost || 0)) }}</template>
          </PColumn>
        </PDataTable>

        <div class="checkout-totals">
          <span class="checkout-totals__grand">Return total <strong>{{ formatCurrency(returnTotal) }}</strong></span>
        </div>

        <div class="dialog-actions">
          <PButton type="button" label="Cancel" severity="secondary" outlined @click="returnDialogVisible = false" />
          <PButton type="submit" icon="pi pi-undo" label="Post return" :loading="saving" />
        </div>
      </form>
    </PDialog>
  </section>
</template>

<script setup>
import { computed, onMounted, reactive, ref } from 'vue'
import BarChart from '../components/BarChart.vue'
import MetricCard from '../components/MetricCard.vue'
import { addDaysISO, currencyCode, formatCurrency, formatDate, formatNumber, toISODate, todayISO } from '../lib/formatters'
import {
  fetchPurchaseManagement,
  processPurchaseReturn,
  receivePurchase,
  savePurchaseOrder,
  saveSupplier,
  updatePurchaseOrderStatus,
  updateSupplierInvoiceStatus,
} from '../services/purchaseService'
import { useAuthStore } from '../stores/authStore'

const auth = useAuthStore()
const loading = ref(false)
const saving = ref(false)
const error = ref('')
const successMessage = ref('')
const formError = ref('')
const purchaseData = ref(null)
const orderSearch = ref('')
const receiptSearch = ref('')
const invoiceSearch = ref('')
const supplierSearch = ref('')
const returnSearch = ref('')
const supplierDialogVisible = ref(false)
const orderDialogVisible = ref(false)
const receiveDialogVisible = ref(false)
const invoiceDialogVisible = ref(false)
const returnDialogVisible = ref(false)
const editingSupplier = ref(null)
const editingOrder = ref(null)
const selectedReceiveOrder = ref(null)
const selectedInvoice = ref(null)
const selectedReturnReceipt = ref(null)

const filters = reactive({
  from: new Date(`${addDaysISO(-29)}T00:00:00`),
  to: new Date(`${todayISO()}T00:00:00`),
  branchId: null,
  search: '',
})

const supplierForm = reactive(createSupplierForm())
const orderForm = reactive(createOrderForm())
const receiveForm = reactive(createReceiveForm())
const invoiceForm = reactive(createInvoiceForm())
const returnForm = reactive(createReturnForm())

const invoiceStatusOptions = [
  { label: 'Pending', value: 'pending' },
  { label: 'Partial', value: 'partial' },
  { label: 'Paid', value: 'paid' },
  { label: 'Voided', value: 'voided' },
]

const isBranchLocked = computed(() => auth.state.profile?.role === 'manager')
const canManagePurchases = computed(() => purchaseData.value?.can_manage_purchases && ['admin', 'manager'].includes(auth.state.profile?.role))
const canApprovePurchases = computed(() => purchaseData.value?.can_approve_purchases)
const canReceivePurchases = computed(() => purchaseData.value?.can_receive_purchases)
const branchFilterOptions = computed(() => [{ id: null, name: 'All branches' }, ...(purchaseData.value?.branches || [])])
const branchOptions = computed(() => purchaseData.value?.branches || [])
const supplierOptions = computed(() =>
  (purchaseData.value?.suppliers || []).map((supplier) => ({
    label: `${supplier.supplier_code} - ${supplier.name}`,
    value: supplier.id,
  })),
)
const productOptions = computed(() =>
  (purchaseData.value?.products || []).map((product) => ({
    label: `${product.sku} - ${product.name}`,
    value: product.id,
  })),
)
const periodLabel = computed(() => {
  const from = purchaseData.value?.period?.from || toISODate(filters.from)
  const to = purchaseData.value?.period?.to || toISODate(filters.to)

  return `${formatDate(from)} to ${formatDate(to)}`
})

const filteredOrders = computed(() => {
  const query = orderSearch.value.toLowerCase()
  const rows = purchaseData.value?.purchase_orders || []
  if (!query) return rows

  return rows.filter((row) =>
    [row.po_number, row.status, row.supplier_name, row.supplier_code, row.branch_name, row.branch_code, row.notes]
      .filter(Boolean)
      .some((value) => String(value).toLowerCase().includes(query)),
  )
})

const filteredReceipts = computed(() => {
  const query = receiptSearch.value.toLowerCase()
  const rows = purchaseData.value?.receipts || []
  if (!query) return rows

  return rows.filter((row) =>
    [row.receipt_number, row.supplier_invoice_number, row.po_number, row.supplier_name, row.branch_name]
      .filter(Boolean)
      .some((value) => String(value).toLowerCase().includes(query)),
  )
})

const filteredInvoices = computed(() => {
  const query = invoiceSearch.value.toLowerCase()
  const rows = purchaseData.value?.supplier_invoices || []
  if (!query) return rows

  return rows.filter((row) =>
    [row.invoice_number, row.receipt_number, row.po_number, row.supplier_name, row.branch_name, row.status]
      .filter(Boolean)
      .some((value) => String(value).toLowerCase().includes(query)),
  )
})

const filteredSuppliers = computed(() => {
  const query = supplierSearch.value.toLowerCase()
  const rows = purchaseData.value?.suppliers || []
  if (!query) return rows

  return rows.filter((row) =>
    [row.supplier_code, row.name, row.contact_person, row.phone, row.email, row.tin]
      .filter(Boolean)
      .some((value) => String(value).toLowerCase().includes(query)),
  )
})

const filteredReturns = computed(() => {
  const query = returnSearch.value.toLowerCase()
  const rows = purchaseData.value?.purchase_returns || []
  if (!query) return rows

  return rows.filter((row) =>
    [row.return_number, row.receipt_number, row.po_number, row.supplier_name, row.branch_name, row.reason]
      .filter(Boolean)
      .some((value) => String(value).toLowerCase().includes(query)),
  )
})

const orderSubtotal = computed(() =>
  roundMoney(orderForm.items.reduce((total, item) => total + Number(item.quantity_ordered || 0) * Number(item.unit_cost || 0), 0)),
)
const orderTaxTotal = computed(() =>
  roundMoney(orderForm.items.reduce((total, item) => total + purchaseLineTax(item), 0)),
)
const orderTotal = computed(() => roundMoney(orderSubtotal.value + orderTaxTotal.value))
const receiveSubtotal = computed(() =>
  roundMoney(receiveForm.items.reduce((total, item) => total + Number(item.quantity_received || 0) * Number(item.unit_cost || 0), 0)),
)
const receiveTaxTotal = computed(() =>
  roundMoney(receiveForm.items.reduce((total, item) => total + receiveLineTax(item), 0)),
)
const receiveTotal = computed(() => roundMoney(receiveSubtotal.value + receiveTaxTotal.value))
const returnTotal = computed(() =>
  roundMoney(returnForm.items.reduce((total, item) => total + Number(item.quantity_returned || 0) * Number(item.unit_cost || 0), 0)),
)

function createSupplierForm() {
  return {
    supplier_code: '',
    name: '',
    contact_person: '',
    phone: '',
    email: '',
    tin: '',
    address: '',
    payment_terms_days: 30,
    credit_limit: 0,
    is_active: true,
    notes: '',
  }
}

function createOrderForm() {
  return {
    branch_id: null,
    supplier_id: null,
    order_date: new Date(`${todayISO()}T00:00:00`),
    expected_date: null,
    notes: '',
    items: [newOrderItem()],
  }
}

function createReceiveForm() {
  return {
    purchase_order_id: null,
    branch_id: null,
    supplier_id: null,
    receipt_date: new Date(`${todayISO()}T00:00:00`),
    supplier_invoice_number: '',
    invoice_date: new Date(`${todayISO()}T00:00:00`),
    due_date: null,
    notes: '',
    items: [newReceiveItem()],
  }
}

function createInvoiceForm() {
  return {
    status: 'pending',
    paid_amount: 0,
    notes: '',
  }
}

function createReturnForm() {
  return {
    receipt_id: null,
    reason: '',
    notes: '',
    items: [],
  }
}

function localKey() {
  return `${Date.now()}-${Math.random()}`
}

function newOrderItem(payload = {}) {
  return {
    local_key: localKey(),
    product_id: payload.product_id || null,
    product_variant_id: payload.product_variant_id || null,
    quantity_ordered: Number(payload.quantity_ordered ?? 1),
    unit_cost: Number(payload.unit_cost || 0),
    tax_rate: Number(payload.tax_rate ?? 12),
  }
}

function newReceiveItem(payload = {}) {
  return {
    local_key: localKey(),
    purchase_order_item_id: payload.purchase_order_item_id || null,
    product_id: payload.product_id || null,
    product_variant_id: payload.product_variant_id || null,
    product_name: payload.product_name || '',
    variant_name: payload.variant_name || '',
    remaining_quantity: Number(payload.remaining_quantity || 0),
    quantity_received: Number(payload.quantity_received ?? 1),
    unit_cost: Number(payload.unit_cost || 0),
    tax_rate: Number(payload.tax_rate ?? 12),
    batch_number: payload.batch_number || '',
    expiry_date: null,
  }
}

function resetObject(target, source) {
  Object.keys(target).forEach((key) => {
    delete target[key]
  })
  Object.assign(target, source)
}

function dateValue(value) {
  return value ? new Date(`${value}T00:00:00`) : null
}

function normalizeDate(value) {
  return toISODate(value) || null
}

function roundMoney(value) {
  return Math.round(Number(value || 0) * 100) / 100
}

function defaultBranchId() {
  return filters.branchId || auth.state.profile?.branch_id || purchaseData.value?.branches?.[0]?.id || null
}

function selectedProduct(productId) {
  return (purchaseData.value?.products || []).find((product) => product.id === productId)
}

function selectedVariant(productId, variantId) {
  return selectedProduct(productId)?.variants?.find((variant) => variant.id === variantId)
}

function variantOptionsForProduct(productId) {
  return (selectedProduct(productId)?.variants || []).map((variant) => ({
    label: `${variant.variant_name} - ${variant.sku}`,
    value: variant.id,
  }))
}

function onOrderProductChange(item) {
  const product = selectedProduct(item.product_id)
  item.product_variant_id = null
  item.unit_cost = Number(product?.cost_price || 0)
}

function onOrderVariantChange(item) {
  const variant = selectedVariant(item.product_id, item.product_variant_id)
  if (variant) item.unit_cost = Number(variant.cost_price || item.unit_cost || 0)
}

function onReceiveProductChange(item) {
  const product = selectedProduct(item.product_id)
  item.product_variant_id = null
  item.unit_cost = Number(product?.cost_price || 0)
}

function onReceiveVariantChange(item) {
  const variant = selectedVariant(item.product_id, item.product_variant_id)
  if (variant) item.unit_cost = Number(variant.cost_price || item.unit_cost || 0)
}

function purchaseLineTax(item) {
  return roundMoney(Number(item.quantity_ordered || 0) * Number(item.unit_cost || 0) * (Number(item.tax_rate || 0) / 100))
}

function purchaseLineTotal(item) {
  return roundMoney(Number(item.quantity_ordered || 0) * Number(item.unit_cost || 0) + purchaseLineTax(item))
}

function receiveLineTax(item) {
  return roundMoney(Number(item.quantity_received || 0) * Number(item.unit_cost || 0) * (Number(item.tax_rate || 0) / 100))
}

function receiveLineTotal(item) {
  return roundMoney(Number(item.quantity_received || 0) * Number(item.unit_cost || 0) + receiveLineTax(item))
}

function canEditOrder(order) {
  return ['draft', 'submitted', 'approved'].includes(order.status) && Number(order.received_quantity || 0) === 0
}

function canReceiveOrder(order) {
  return ['submitted', 'approved', 'partially_received'].includes(order.status) && Number(order.received_quantity || 0) < Number(order.ordered_quantity || 0)
}

function receiptHasReturnableItems(receipt) {
  return (receipt.items || []).some((item) => Number(item.quantity_received || 0) - Number(item.quantity_returned || 0) > 0)
}

function clearFeedback() {
  formError.value = ''
  error.value = ''
  successMessage.value = ''
}

async function loadPurchases() {
  loading.value = true
  error.value = ''
  successMessage.value = ''

  try {
    purchaseData.value = await fetchPurchaseManagement({
      from: normalizeDate(filters.from),
      to: normalizeDate(filters.to),
      branchId: filters.branchId,
      search: filters.search,
    })

    if (isBranchLocked.value && !filters.branchId) {
      filters.branchId = purchaseData.value.branches[0]?.id || auth.state.profile?.branch_id || null
    }
  } catch (loadError) {
    error.value = loadError.message
  } finally {
    loading.value = false
  }
}

function openSupplier(supplier = null) {
  editingSupplier.value = supplier
  resetObject(supplierForm, {
    ...createSupplierForm(),
    ...(supplier || {}),
  })
  formError.value = ''
  supplierDialogVisible.value = true
}

function openPurchaseOrder(order = null) {
  editingOrder.value = order
  resetObject(orderForm, {
    ...createOrderForm(),
    branch_id: order?.branch_id || defaultBranchId(),
    supplier_id: order?.supplier_id || null,
    order_date: dateValue(order?.order_date) || new Date(`${todayISO()}T00:00:00`),
    expected_date: dateValue(order?.expected_date),
    notes: order?.notes || '',
    items: order?.items?.length ? order.items.map(newOrderItem) : [newOrderItem()],
  })
  formError.value = ''
  orderDialogVisible.value = true
}

function openReceive(order = null) {
  selectedReceiveOrder.value = order
  const rows = order?.items
    ?.map((item) => {
      const remaining = Number(item.quantity_ordered || 0) - Number(item.quantity_received || 0)
      return newReceiveItem({
        purchase_order_item_id: item.id,
        product_id: item.product_id,
        product_variant_id: item.product_variant_id,
        product_name: item.product_name,
        variant_name: item.variant_name,
        remaining_quantity: remaining,
        quantity_received: Math.max(remaining, 0),
        unit_cost: item.unit_cost,
        tax_rate: item.tax_rate,
      })
    })
    .filter((item) => Number(item.remaining_quantity || 0) > 0)

  resetObject(receiveForm, {
    ...createReceiveForm(),
    purchase_order_id: order?.id || null,
    branch_id: order?.branch_id || defaultBranchId(),
    supplier_id: order?.supplier_id || null,
    items: rows?.length ? rows : [newReceiveItem()],
  })
  formError.value = ''
  receiveDialogVisible.value = true
}

function openInvoiceDialog(invoice) {
  selectedInvoice.value = invoice
  resetObject(invoiceForm, {
    status: invoice.status,
    paid_amount: invoice.status === 'paid' ? invoice.amount : invoice.paid_amount,
    notes: invoice.notes || '',
  })
  formError.value = ''
  invoiceDialogVisible.value = true
}

function openPurchaseReturn(receipt) {
  selectedReturnReceipt.value = receipt
  resetObject(returnForm, {
    ...createReturnForm(),
    receipt_id: receipt.id,
    items: (receipt.items || [])
      .map((item) => ({
        receipt_item_id: item.id,
        product_name: item.product_name,
        variant_name: item.variant_name,
        sku: item.sku,
        batch_number: item.batch_number,
        unit_cost: item.unit_cost,
        available_quantity: Number(item.quantity_received || 0) - Number(item.quantity_returned || 0),
        quantity_returned: 0,
      }))
      .filter((item) => item.available_quantity > 0),
  })
  formError.value = ''
  returnDialogVisible.value = true
}

function addOrderItem() {
  orderForm.items.push(newOrderItem())
}

function removeOrderItem(index) {
  orderForm.items.splice(index, 1)
}

function addReceiveItem() {
  receiveForm.items.push(newReceiveItem())
}

function removeReceiveItem(index) {
  receiveForm.items.splice(index, 1)
}

function validateSupplier() {
  if (!supplierForm.name.trim()) {
    formError.value = 'Supplier name is required.'
    return false
  }

  return true
}

function validateOrder() {
  if (!orderForm.branch_id || !orderForm.supplier_id) {
    formError.value = 'Branch and supplier are required.'
    return false
  }

  if (!orderForm.items.length || orderForm.items.some((item) => !item.product_id || Number(item.quantity_ordered || 0) <= 0)) {
    formError.value = 'Every purchase order item needs a product and quantity greater than zero.'
    return false
  }

  return true
}

function validateReceive() {
  if (!receiveForm.branch_id || !receiveForm.supplier_id) {
    formError.value = 'Branch and supplier are required for receiving.'
    return false
  }

  const rows = receiveForm.items.filter((item) => Number(item.quantity_received || 0) > 0)
  if (!rows.length || rows.some((item) => !item.product_id)) {
    formError.value = 'Add at least one received item with a product and quantity.'
    return false
  }

  if (rows.some((item) => item.remaining_quantity && Number(item.quantity_received || 0) > Number(item.remaining_quantity || 0))) {
    formError.value = 'Received quantity cannot exceed the remaining PO quantity.'
    return false
  }

  return true
}

function validateInvoice() {
  if (!invoiceForm.status) {
    formError.value = 'Invoice status is required.'
    return false
  }

  if (Number(invoiceForm.paid_amount || 0) < 0 || Number(invoiceForm.paid_amount || 0) > Number(selectedInvoice.value?.amount || 0)) {
    formError.value = 'Paid amount must be between zero and the invoice amount.'
    return false
  }

  return true
}

function validateReturn() {
  if (!returnForm.reason.trim()) {
    formError.value = 'Purchase return reason is required.'
    return false
  }

  const rows = returnForm.items.filter((item) => Number(item.quantity_returned || 0) > 0)
  if (!rows.length) {
    formError.value = 'Add at least one purchase return quantity.'
    return false
  }

  if (rows.some((item) => Number(item.quantity_returned || 0) > Number(item.available_quantity || 0))) {
    formError.value = 'Return quantity cannot exceed the available received quantity.'
    return false
  }

  return true
}

async function submitSupplier() {
  clearFeedback()
  saving.value = true

  try {
    if (!validateSupplier()) return
    purchaseData.value = await saveSupplier(editingSupplier.value?.id, { ...supplierForm })
    supplierDialogVisible.value = false
    successMessage.value = 'Supplier was saved.'
  } catch (saveError) {
    formError.value = saveError.message
  } finally {
    saving.value = false
  }
}

async function submitPurchaseOrder() {
  clearFeedback()
  saving.value = true

  try {
    if (!validateOrder()) return
    purchaseData.value = await savePurchaseOrder(editingOrder.value?.id, {
      branch_id: orderForm.branch_id,
      supplier_id: orderForm.supplier_id,
      order_date: normalizeDate(orderForm.order_date),
      expected_date: normalizeDate(orderForm.expected_date),
      notes: orderForm.notes,
      items: orderForm.items.map((item) => ({
        product_id: item.product_id,
        product_variant_id: item.product_variant_id,
        quantity_ordered: Number(item.quantity_ordered || 0),
        unit_cost: Number(item.unit_cost || 0),
        tax_rate: Number(item.tax_rate || 0),
      })),
    })
    orderDialogVisible.value = false
    successMessage.value = 'Purchase order was saved.'
  } catch (saveError) {
    formError.value = saveError.message
  } finally {
    saving.value = false
  }
}

async function changeOrderStatus(order, status) {
  let reason = ''
  if (status === 'cancelled') {
    reason = window.prompt(`Reason for cancelling ${order.po_number}?`) || ''
    if (!reason.trim()) return
  }

  loading.value = true
  error.value = ''
  successMessage.value = ''

  try {
    purchaseData.value = await updatePurchaseOrderStatus(order.id, status, reason)
    successMessage.value = `${order.po_number} is now ${statusLabel(status).toLowerCase()}.`
  } catch (statusError) {
    error.value = statusError.message
  } finally {
    loading.value = false
  }
}

async function submitReceive() {
  clearFeedback()
  saving.value = true

  try {
    if (!validateReceive()) return
    purchaseData.value = await receivePurchase({
      purchase_order_id: receiveForm.purchase_order_id,
      branch_id: receiveForm.branch_id,
      supplier_id: receiveForm.supplier_id,
      receipt_date: normalizeDate(receiveForm.receipt_date),
      supplier_invoice_number: receiveForm.supplier_invoice_number,
      invoice_date: normalizeDate(receiveForm.invoice_date),
      due_date: normalizeDate(receiveForm.due_date),
      notes: receiveForm.notes,
      items: receiveForm.items
        .filter((item) => Number(item.quantity_received || 0) > 0)
        .map((item) => ({
          purchase_order_item_id: item.purchase_order_item_id,
          product_id: item.product_id,
          product_variant_id: item.product_variant_id,
          quantity_received: Number(item.quantity_received || 0),
          unit_cost: Number(item.unit_cost || 0),
          tax_rate: Number(item.tax_rate || 0),
          batch_number: item.batch_number,
          expiry_date: normalizeDate(item.expiry_date),
        })),
    })
    receiveDialogVisible.value = false
    successMessage.value = 'Receiving was posted to inventory and supplier invoices.'
  } catch (saveError) {
    formError.value = saveError.message
  } finally {
    saving.value = false
  }
}

async function submitInvoiceStatus() {
  clearFeedback()
  saving.value = true

  try {
    if (!validateInvoice()) return
    purchaseData.value = await updateSupplierInvoiceStatus(
      selectedInvoice.value.id,
      invoiceForm.status,
      Number(invoiceForm.paid_amount || 0),
      invoiceForm.notes,
    )
    invoiceDialogVisible.value = false
    successMessage.value = 'Supplier invoice was updated.'
  } catch (saveError) {
    formError.value = saveError.message
  } finally {
    saving.value = false
  }
}

async function submitPurchaseReturn() {
  clearFeedback()
  saving.value = true

  try {
    if (!validateReturn()) return
    purchaseData.value = await processPurchaseReturn({
      receipt_id: returnForm.receipt_id,
      reason: returnForm.reason,
      notes: returnForm.notes,
      items: returnForm.items
        .filter((item) => Number(item.quantity_returned || 0) > 0)
        .map((item) => ({
          receipt_item_id: item.receipt_item_id,
          quantity_returned: Number(item.quantity_returned || 0),
        })),
    })
    returnDialogVisible.value = false
    successMessage.value = 'Purchase return was posted and inventory was reduced.'
  } catch (saveError) {
    formError.value = saveError.message
  } finally {
    saving.value = false
  }
}

function statusLabel(value) {
  const labels = {
    draft: 'Draft',
    submitted: 'Submitted',
    approved: 'Approved',
    partially_received: 'Partially received',
    received: 'Received',
    cancelled: 'Cancelled',
    closed: 'Closed',
  }

  return labels[value] || value || '-'
}

function statusSeverity(value) {
  if (value === 'received') return 'success'
  if (value === 'approved') return 'info'
  if (value === 'submitted' || value === 'partially_received') return 'warn'
  if (value === 'cancelled') return 'danger'
  return 'secondary'
}

function invoiceStatusLabel(value) {
  const labels = {
    pending: 'Pending',
    partial: 'Partial',
    paid: 'Paid',
    voided: 'Voided',
  }

  return labels[value] || value || '-'
}

function invoiceStatusSeverity(value) {
  if (value === 'paid') return 'success'
  if (value === 'partial') return 'warn'
  if (value === 'voided') return 'danger'
  return 'info'
}

function formatDateTime(value) {
  if (!value) return '-'

  return new Intl.DateTimeFormat('en-PH', {
    month: 'short',
    day: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(value))
}

onMounted(loadPurchases)
</script>
