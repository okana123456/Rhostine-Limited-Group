import { json } from "../_shared/http.ts";
import { adminClient } from "../_shared/supabase.ts";

function parseMpesaTime(value) {
  const text = String(value || "");
  const match = text.match(/^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})$/);
  return match ? `${match[1]}-${match[2]}-${match[3]}T${match[4]}:${match[5]}:${match[6]}+03:00` : new Date().toISOString();
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ ResultCode: 0, ResultDesc: "Accepted" });
  try {
    const businessId = new URL(req.url).pathname.split("/").filter(Boolean).pop();
    const payload = await req.json();
    const admin = adminClient();
    const { data: business } = await admin.from("rh_businesses").select("id").eq("id", businessId).maybeSingle();
    if (!business) return json({ ResultCode: 1, ResultDesc: "Unknown business" }, 404);

    const transId = String(payload.TransID || payload.TransactionID || "").trim();
    const accountReference = String(payload.BillRefNumber || payload.AccountReference || "").trim();
    if (!transId) return json({ ResultCode: 1, ResultDesc: "Transaction ID required" }, 400);

    const { data: group } = await admin.from("rh_groups").select("id").eq("business_id", businessId).eq("group_code", accountReference).maybeSingle();
    const row = {
      business_id: businessId, group_id: group?.id || null, transaction_id: transId, trans_id: transId,
      transaction_time: parseMpesaTime(payload.TransTime), amount: Number(payload.TransAmount || payload.Amount || 0),
      msisdn: String(payload.MSISDN || payload.PhoneNumber || ""), account_reference: accountReference,
      transaction_type: String(payload.TransactionType || "C2B"), allocation_status: group ? "unallocated" : "unmatched",
      raw_payload: payload,
    };
    const { error } = await admin.from("rh_mpesa_transactions").upsert(row, { onConflict: "trans_id" });
    if (error) throw error;
    return json({ ResultCode: 0, ResultDesc: "Accepted" });
  } catch (error) {
    console.error("Collections callback error", error);
    return json({ ResultCode: 1, ResultDesc: "Unable to record transaction" }, 500);
  }
});
