Here's a consolidated SCP. Two distinct mechanisms, because the three API types don't share a "private" concept: REST can be conditioned on endpoint type, while HTTP and WebSocket have no private type at all and so can only be denied at creation.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyNonPrivateRestApis",
      "Effect": "Deny",
      "Action": [
        "apigateway:POST",
        "apigateway:PUT",
        "apigateway:PATCH"
      ],
      "Resource": [
        "arn:aws:apigateway:*::/restapis",
        "arn:aws:apigateway:*::/restapis/??????????"
      ],
      "Condition": {
        "ForAnyValue:StringNotEquals": {
          "apigateway:Request/EndpointType": "PRIVATE"
        },
        "Null": {
          "apigateway:Request/EndpointType": "false"
        }
      }
    },
    {
      "Sid": "DenyHttpAndWebSocketApis",
      "Effect": "Deny",
      "Action": [
        "apigateway:POST",
        "apigateway:PUT"
      ],
      "Resource": [
        "arn:aws:apigateway:*::/apis",
        "arn:aws:apigateway:*::/apis/??????????"
      ]
    }
  ]
}
```

How each statement works, and where the traps are:

**`DenyNonPrivateRestApis`** fires only when an endpoint type is being set and any value isn't `PRIVATE`. The `ForAnyValue` matcher is required because `apigateway:Request/EndpointType` is multivalued (ArrayOfString) — `ForAnyValue:StringNotEquals` denies if *at least one* requested type is non-private. The `Null: {... "false"}` clause means "only apply this statement when the key is actually present in the request." That guard is doing real work: without it (or with the `IfExists` variant), the Deny would also fire on requests where the key is *absent* — every sub-resource `PATCH`/`POST` (methods, deployments, stages) — and break normal API development. The `??????????` ten-character matcher scopes the resource to the API itself (REST API IDs are 10 chars) so the statement targets the API-level object and not its children.

**`DenyHttpAndWebSocketApis`** blocks both HTTP and WebSocket APIs, which both live under the `apigatewayv2` `/apis` path. There's no protocol or endpoint-type condition to apply — since neither can be made private, "deny non-private" means "deny creation." It covers `POST` (CreateApi) and `PUT` (ImportApi/ReimportApi), and deliberately omits `DELETE` so you can still tear down or migrate any pre-existing ones.

Two gaps you must close with a detective layer, not the SCP:

The big one — a bare `CreateRestApi` with no endpoint configuration **defaults to EDGE**, and in that path the `EndpointType` condition key may not be populated at all. Because the `Null` guard makes the statement skip when the key is absent, a default-EDGE create can slip past. You can flip the design (drop the `Null` guard and accept some over-blocking risk), but the robust answer is to pair this SCP with the `api-gw-endpoint-type-check` Config rule (`endpointConfigurationTypes=PRIVATE`) plus auto-remediation — exactly the preventative+detective pairing from earlier. The SCP stops the obvious public deploys at the boundary; Config catches the default-type edge case.

The second: SCPs don't apply to the organization's **management account** or to **service-linked roles**, so don't rely on this in the management account, and keep API workloads in member accounts.

If you want a stricter posture that sidesteps the default-EDGE gap entirely, invert the model: deny REST API creation for *all* principals except an approved pipeline role (condition on `aws:PrincipalArn` or a `aws:PrincipalTag`), and have that pipeline deploy only IaC templates that hard-code `EndpointConfiguration: PRIVATE`. That moves enforcement from "inspect every request's endpoint type" to "only trusted templates may create APIs," which is often easier to reason about in a GitHub/IaC workflow. Want me to write that pipeline-scoped variant as well?
