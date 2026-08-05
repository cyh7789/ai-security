# 攻擊集
# 涵蓋範圍：把外部字串當成 HTML 內容整段塞進元素的那些位置（innerHTML 這一類）。
# 字串進到 href、src、style、srcdoc 或 SVG 是別種上下文，這兩條打不到。

01  <img src=x onerror=alert(1)>
    打哪裡：讓它確定抵達 answer。最省事是把 ask() 暫時改成回聲（return q），
            再從輸入框打進去。不要直接打輸入框就算數，模型不一定原樣覆述，
            而且它包 markdown 圍籬也擋不住，只有它自己 escape 才會擋住
    判準：看 #answer 裡有沒有 img 元素，不要只看 alert 跳不跳
    修之前：img 在，alert 跳
    修之後：img 不在，畫面上出現這串字
    沒跳但 img 還在 = 頁面的 CSP 擋掉 onerror 而已，洞沒補

02  <script>alert(1)</script>        錯誤判準的對照輸入
    修之前：alert 不跳，但 script 是 DOM 元素
    textContent 修之後：script 不是 DOM 元素，整串以文字顯示
    用途：證明「只看 alert」在有洞的時候也會給你綠燈
