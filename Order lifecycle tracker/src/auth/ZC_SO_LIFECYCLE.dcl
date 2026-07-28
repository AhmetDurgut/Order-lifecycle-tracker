// =========================================================================
// Access Control : ZC_SO_LIFECYCLE
// Purpose        : Sales-organization-based authorization for the Sales
//                   Order Lifecycle header view
// Layer          : Access Control (.dcl)
// Target         : S/4HANA
//
// Notes:
// - The consumption view ZC_SO_LIFECYCLE declares
//   @AccessControl.authorizationCheck: #CHECK, which activates this DCL.
//   Users only see orders from sales organizations they're authorized for.
// - Uses the standard SD auth object V_VBAK_VKO (Sales Organization /
//   Distribution Channel / Division), with activity 03 (display).
// - The fields SalesOrganization / DistributionChannel / Division were
//   deliberately projected through the interface and consumption views
//   so this DCL can reference them.
// =========================================================================

@EndUserText.label: 'Auth: Sales Order Lifecycle (Header)'
@MappingRole: true
define role ZC_SO_LIFECYCLE_AUTH {

  grant
    select
      on ZC_SO_LIFECYCLE
        where ( SalesOrganization, DistributionChannel, Division ) =
          aspect pfcg_auth( V_VBAK_VKO, VKORG, VTWEG, SPART, ACTVT = '03' );

}
