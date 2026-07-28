// =========================================================================
// Access Control : ZC_SO_LIFECYCLE_ITEM
// Purpose        : Sales-organization-based authorization for the Sales
//                   Order Lifecycle item view
// Layer          : Access Control (.dcl)
// Target         : S/4HANA
//
// Notes:
// - The item view ZC_SO_LIFECYCLE_ITEM declares
//   @AccessControl.authorizationCheck: #CHECK.
// - The item view has no sales org fields of its own, so authorization is
//   INHERITED from the header view ZC_SO_LIFECYCLE through the
//   _SalesOrder association, using "inheriting conditions from entity".
//   This guarantees a user can only see items of orders they're already
//   authorized to see - no separate rule to keep in sync.
// - This is the cleaner pattern than repeating the V_VBAK_VKO check here,
//   because the item reuses the header's authorization automatically.
// =========================================================================

@EndUserText.label: 'Auth: Sales Order Lifecycle (Item)'
@MappingRole: true
define role ZC_SO_LIFECYCLE_ITEM_AUTH {

  grant
    select
      on ZC_SO_LIFECYCLE_ITEM
        where inheriting conditions from entity ZC_SO_LIFECYCLE
          via association _SalesOrder;

}
