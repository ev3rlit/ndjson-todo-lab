<template>
  <div class="slidev-layout lab-layout two-cols-header lab-two-cols-header">
    <header class="lab-slide-header">
      <slot />
    </header>

    <div class="lab-two-cols">
      <section class="lab-pane lab-pane-left">
        <slot name="left" />
      </section>
      <section class="lab-pane lab-pane-right">
        <slot name="right" />
      </section>
    </div>
  </div>
</template>
